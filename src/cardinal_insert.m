#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <libproc.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <spawn.h>
#include <mach-o/dyld.h>
#include <poll.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

#ifndef TARGET_PATH
#define TARGET_PATH "/Applications/CardinalNative.app/Contents/MacOS/CardinalNative"
#endif
#ifndef TARGET_BUNDLE
#define TARGET_BUNDLE "studio.kx.distrho.cardinal.native"
#endif
#ifndef RUNTIME_SUFFIX
#define RUNTIME_SUFFIX "v2"
#endif
#ifndef HOLD_MS
#define HOLD_MS 12
#endif
#define CAPACITY 4
#define EXPIRY 2.0
#define IDLE 0.4
extern char **environ;
static char runtimeDir[PATH_MAX],socketPath[104],lockPath[PATH_MAX],selfPath[PATH_MAX];
static const CGEventFlags modifierMask=kCGEventFlagMaskControl|kCGEventFlagMaskAlternate|kCGEventFlagMaskCommand|kCGEventFlagMaskShift;
static double clockNow(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec/1e9; }
static void pump(double seconds) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,true); }
static void logMessage(NSString *s) { fprintf(stderr,"%.6f pid=%d %s\n",clockNow(),getpid(),s.UTF8String); }
static pid_t target(void) {
  NSRunningApplication *a=NSWorkspace.sharedWorkspace.frontmostApplication;
  char p[PROC_PIDPATHINFO_MAXSIZE]={0};
  if(![a.bundleIdentifier isEqualToString:@TARGET_BUNDLE] || proc_pidpath(a.processIdentifier,p,sizeof(p))<=0 || strcmp(p,TARGET_PATH)) return 0;
  return a.processIdentifier;
}
static BOOL initPaths(void) {
  char tmp[PATH_MAX];
  if(!confstr(_CS_DARWIN_USER_TEMP_DIR,tmp,sizeof(tmp))) return NO;
  if(snprintf(runtimeDir,sizeof(runtimeDir),"%scardinal-insert-%u-%s",tmp,getuid(),RUNTIME_SUFFIX)>=(int)sizeof(runtimeDir)) return NO;
  if(mkdir(runtimeDir,0700) && errno!=EEXIST) return NO;
  struct stat st;
  if(lstat(runtimeDir,&st) || !S_ISDIR(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&077)!=0) return NO;
  if(snprintf(socketPath,sizeof(socketPath),"%s/s",runtimeDir)>=(int)sizeof(socketPath)) return NO;
  snprintf(lockPath,sizeof(lockPath),"%s/l",runtimeDir);
  char exe[PATH_MAX];uint32_t n=sizeof(exe);
  return !_NSGetExecutablePath(exe,&n) && realpath(exe,selfPath)!=NULL;
}
typedef struct { uint32_t version;pid_t sender;pid_t target;double created; } Request;
typedef struct { Request request;unsigned long epoch; } Pending;
static int openConnection(void) {
  int s=socket(AF_UNIX,SOCK_STREAM,0);if(s<0)return -1;
  int one=1;setsockopt(s,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
  fcntl(s,F_SETFL,O_NONBLOCK);
  struct sockaddr_un a={0};a.sun_family=AF_UNIX;strlcpy(a.sun_path,socketPath,sizeof(a.sun_path));
  if(connect(s,(struct sockaddr *)&a,sizeof(a))) {
    if(errno!=EINPROGRESS) {close(s);return -1;}
    struct pollfd ready={.fd=s,.events=POLLOUT};int error=0;socklen_t length=sizeof(error);
    if(poll(&ready,1,5)<=0 || getsockopt(s,SOL_SOCKET,SO_ERROR,&error,&length) || error) {close(s);return -1;}
  }
  fcntl(s,F_SETFL,0);return s;
}
static BOOL startWorker(void) {
  posix_spawnattr_t attr;posix_spawnattr_init(&attr);
  posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attr,0);
  posix_spawn_file_actions_t acts;posix_spawn_file_actions_init(&acts);
  posix_spawn_file_actions_addopen(&acts,STDIN_FILENO,"/dev/null",O_RDONLY,0);
  char *args[]={selfPath,"--worker",NULL};pid_t child=0;
  int result=posix_spawn(&child,selfPath,&acts,&attr,args,environ);
  posix_spawn_file_actions_destroy(&acts);posix_spawnattr_destroy(&attr);
  return result==0;
}
static int launch(void) {
  Request r={.version=2,.sender=getpid(),.created=clockNow(),.target=target()};
  char parent[PROC_PIDPATHINFO_MAXSIZE]={0};proc_pidpath(getppid(),parent,sizeof(parent));
  logMessage([NSString stringWithFormat:@"TRIGGER request=%d parent=%s target=%d",r.sender,parent,r.target]);
  if(!r.target) {logMessage(@"SKIPPED wrong foreground");return 4;}
  int s=openConnection();
  if(s<0) {
    if(!startWorker()) {logMessage(@"ERROR worker spawn failed");return 5;}
    double deadline=clockNow()+.25;
    do {usleep(1000);s=openConnection();} while(s<0 && clockNow()<deadline);
  }
  if(s<0) {logMessage(@"DROPPED worker unavailable; no retry after delivery");return 6;}
  struct timeval timeout={.tv_sec=0,.tv_usec=150000};setsockopt(s,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
  // Exactly one submission. Never retry after writing: that could duplicate an edit.
  ssize_t sent=send(s,&r,sizeof(r),0);char ack=0;
  ssize_t got=sent==sizeof(r)?recv(s,&ack,1,0):-1;close(s);
#ifdef TEST_HOLD_LAUNCHER
  usleep(500000);
#endif
  logMessage([NSString stringWithFormat:@"LAUNCH request=%d acknowledged=%d elapsed_ms=%.3f",r.sender,got==1&&ack=='A',(clockNow()-r.created)*1000]);
  return got==1&&ack=='A'?0:7;
}
static CGEventRef nativeEvent(BOOL down) {
  UniChar c=NSInsertFunctionKey;NSString *text=[NSString stringWithCharacters:&c length:1];
  NSEvent *event=[NSEvent keyEventWithType:down?NSEventTypeKeyDown:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];
  return event.CGEvent?CGEventCreateCopy(event.CGEvent):NULL;
}
// 0: cancelled, 1: pair posted, 2: modifier changed during preparation; retry.
static int deliver(Request r) {
  CGEventRef fallbackUp=nativeEvent(NO),down=nativeEvent(YES);
  if(!down || !fallbackUp) {if(down)CFRelease(down);if(fallbackUp)CFRelease(fallbackUp);return NO;}
  if(target()!=r.target) {CFRelease(down);CFRelease(fallbackUp);logMessage(@"DROPPED focus changed before press");return NO;}
  if(CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)&modifierMask) {CFRelease(down);CFRelease(fallbackUp);return 2;}
  sigset_t blocked,previous;sigemptyset(&blocked);
  sigaddset(&blocked,SIGTERM);sigaddset(&blocked,SIGINT);sigaddset(&blocked,SIGHUP);
  sigprocmask(SIG_BLOCK,&blocked,&previous);
  CGEventPostToPid(r.target,down);CFRelease(down);
  logMessage([NSString stringWithFormat:@"DOWN request=%d age_ms=%.3f",r.sender,(clockNow()-r.created)*1000]);
  // Only this detached worker sends events. SIGKILL of a Karabiner launcher
  // cannot split the pair. Always release the original PID, even if focus moves.
  usleep(HOLD_MS*1000);
  CGEventRef up=nativeEvent(NO);
  CGEventPostToPid(r.target,up?up:fallbackUp);if(up)CFRelease(up);CFRelease(fallbackUp);
  logMessage([NSString stringWithFormat:@"UP request=%d age_ms=%.3f",r.sender,(clockNow()-r.created)*1000]);
  sigprocmask(SIG_SETMASK,&previous,NULL);
  return YES;
}
static int worker(void) {
  int lock=open(lockPath,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
  if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) {if(lock>=0)close(lock);return 0;}
  int s=socket(AF_UNIX,SOCK_STREAM,0);if(s<0){close(lock);return 8;}
  fcntl(s,F_SETFL,O_NONBLOCK);fcntl(s,F_SETFD,FD_CLOEXEC);
  unlink(socketPath);
  struct sockaddr_un a={0};a.sun_family=AF_UNIX;strlcpy(a.sun_path,socketPath,sizeof(a.sun_path));
  if(bind(s,(struct sockaddr *)&a,sizeof(a)) || listen(s,CAPACITY)) {close(s);close(lock);return 9;}
  BOOL ax=AXIsProcessTrusted(),post=CGPreflightPostEventAccess();
  logMessage([NSString stringWithFormat:@"WORKER parent=%d AX=%d post=%d hold_ms=%d",getppid(),ax,post,HOLD_MS]);
  if(!ax || !post) {logMessage(@"PERMISSION_REQUIRED no prompt and no event sent");close(s);unlink(socketPath);close(lock);return 3;}
  __block unsigned long epoch=0;
  id observer=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n;++epoch; }];
  Pending pending[CAPACITY];int count=0;double idleSince=clockNow();
  for(;;) { @autoreleasepool {
    pump(.001);
    for(int i=0;i<CAPACITY+1;i++) {
      int c=accept(s,NULL,NULL);if(c<0)break;
      int one=1;setsockopt(c,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
      struct timeval timeout={.tv_sec=0,.tv_usec=10000};setsockopt(c,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
      Request r={0};ssize_t n=recv(c,&r,sizeof(r),MSG_WAITALL);
      double age=clockNow()-r.created;
      uid_t uid;gid_t gid;BOOL peer=getpeereid(c,&uid,&gid)==0&&uid==getuid();
      char ack='R';
      if(peer && n==sizeof(r) && r.version==2 && age>=0 && age<EXPIRY && r.target>0 && target()==r.target && count<CAPACITY) {
        pending[count++]=(Pending){r,epoch};idleSince=clockNow();ack='A';
        logMessage([NSString stringWithFormat:@"ACCEPT request=%d depth=%d",r.sender,count]);
      } else logMessage([NSString stringWithFormat:@"REJECT request=%d depth=%d stale_or_focus_or_full",r.sender,count]);
      send(c,&ack,1,0);close(c);
    }
    if(count) {
      Pending p=pending[0];NSString *reason=p.epoch!=epoch?@"focus_epoch":target()!=p.request.target?@"foreground":clockNow()-p.request.created>=EXPIRY?@"expired":nil;
      BOOL drop=reason!=nil;
      if(drop || !(CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)&modifierMask)) {
        if(drop)logMessage([NSString stringWithFormat:@"DROP request=%d reason=%@",p.request.sender,reason]);
        int result=drop?0:deliver(p.request);
        if(result!=2) {--count;memmove(pending,pending+1,count*sizeof(*pending));idleSince=clockNow();}
      }
    } else if(clockNow()-idleSince>IDLE) break;
    usleep(1000);
  } }
  // Closing the listener causes unaccepted clients to fail rather than silently
  // reporting success. Their launchers never resubmit an uncertain request.
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
  close(s);unlink(socketPath);close(lock);logMessage(@"WORKER_EXIT idle");return 0;
}
int main(int argc,char **argv) { @autoreleasepool {
  setbuf(stderr,NULL);signal(SIGPIPE,SIG_IGN);
  if(argc!=2) return 2;
  if(!strcmp(argv[1],"--check")) {fprintf(stderr,"AX=%d post=%d no event sent\n",AXIsProcessTrusted(),CGPreflightPostEventAccess());return 0;}
  if(!initPaths()) {logMessage(@"ERROR private runtime directory unavailable");return 10;}
  if(!strcmp(argv[1],"--karabiner")) return launch();
  if(!strcmp(argv[1],"--worker")) return worker();
  return 2;
} }
