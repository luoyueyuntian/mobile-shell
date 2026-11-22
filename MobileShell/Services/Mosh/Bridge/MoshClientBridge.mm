#import "MoshClientBridge.h"
#import <mosh/moshiosbridge.h>
#include <errno.h>
#include <locale.h>
#include <sys/ioctl.h>
#include <unistd.h>

static NSString * const MoshClientBridgeErrorDomain = @"MobileShell.MoshClientBridge";

static void MobileShellMoshStateCallback(const void *context, const void *buffer, size_t size) {
    (void)context;
    (void)buffer;
    (void)size;
}

@implementation MoshClientBridgeAdapter
{
    NSString *_host;
    NSString *_port;
    NSString *_key;
    NSString *_predictionMode;
    NSString *_localesBundlePath;
    NSString *_predictOverwrite;
    dispatch_queue_t _runtimeQueue;
    dispatch_queue_t _outputQueue;
    dispatch_source_t _readSource;
    MoshClientOutputHandler _outputHandler;
    MoshClientExitHandler _exitHandler;
    int _stdinReadFD;
    int _stdinWriteFD;
    int _stdoutReadFD;
    int _stdoutWriteFD;
    FILE *_stdinFile;
    FILE *_stdoutFile;
    BOOL _started;
}

- (instancetype)init {
    return [self initWithHost:@""
                        port:@""
                         key:@""
              predictionMode:@"adaptive"
           localesBundlePath:@""
            predictOverwrite:nil];
}

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                         key:(NSString *)key
              predictionMode:(NSString *)predictionMode
           localesBundlePath:(NSString *)localesBundlePath
            predictOverwrite:(NSString * _Nullable)predictOverwrite {
    self = [super init];
    if (!self) {
        return nil;
    }

    _host = [host copy];
    _port = [port copy];
    _key = [key copy];
    _predictionMode = [predictionMode copy];
    _localesBundlePath = [localesBundlePath copy];
    _predictOverwrite = [predictOverwrite copy];
    _runtimeQueue = dispatch_queue_create("MobileShell.MoshClientBridge.runtime", DISPATCH_QUEUE_SERIAL);
    _outputQueue = dispatch_queue_create("MobileShell.MoshClientBridge.output", DISPATCH_QUEUE_SERIAL);
    _stdinReadFD = -1;
    _stdinWriteFD = -1;
    _stdoutReadFD = -1;
    _stdoutWriteFD = -1;
    _stdinFile = NULL;
    _stdoutFile = NULL;
    _started = NO;

    return self;
}

+ (BOOL)isMoshBinaryLinked {
    return &mosh_main != NULL;
}

- (BOOL)startWithOutputHandler:(MoshClientOutputHandler)outputHandler
                   exitHandler:(MoshClientExitHandler)exitHandler
                         error:(NSError **)error {
    if (_started) {
        return YES;
    }

    if (_host.length == 0 || _port.length == 0 || _key.length == 0 || _localesBundlePath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MoshClientBridgeErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing Mosh bridge configuration."}];
        }
        return NO;
    }

    int stdinPipe[2];
    int stdoutPipe[2];
    if (pipe(stdinPipe) != 0 || pipe(stdoutPipe) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:MoshClientBridgeErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create Mosh bridge pipes."}];
        }
        return NO;
    }

    _stdinReadFD = stdinPipe[0];
    _stdinWriteFD = stdinPipe[1];
    _stdoutReadFD = stdoutPipe[0];
    _stdoutWriteFD = stdoutPipe[1];
    _stdinFile = fdopen(_stdinReadFD, "r");
    _stdoutFile = fdopen(_stdoutWriteFD, "w");

    if (_stdinFile == NULL || _stdoutFile == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:MoshClientBridgeErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create Mosh bridge file streams."}];
        }
        return NO;
    }

    setvbuf(_stdoutFile, NULL, _IONBF, 0);
    _outputHandler = [outputHandler copy];
    _exitHandler = [exitHandler copy];
    _started = YES;

    __weak typeof(self) weakSelf = self;
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_stdoutReadFD, 0, _outputQueue);
    dispatch_source_set_event_handler(_readSource, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        char buffer[4096];
        ssize_t count = read(strongSelf->_stdoutReadFD, buffer, sizeof(buffer));
        if (count <= 0) {
            return;
        }

        NSString *output = [[NSString alloc] initWithBytes:buffer
                                                    length:(NSUInteger)count
                                                  encoding:NSUTF8StringEncoding];
        if (output.length == 0) {
            output = [[NSString alloc] initWithBytes:buffer
                                              length:(NSUInteger)count
                                            encoding:NSISOLatin1StringEncoding];
        }
        if (output.length > 0 && strongSelf->_outputHandler) {
            strongSelf->_outputHandler(output);
        }
    });
    dispatch_resume(_readSource);

    dispatch_async(_runtimeQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        setenv("PATH_LOCALE", strongSelf->_localesBundlePath.UTF8String, 1);
        setlocale(LC_ALL, "UTF-8");
        setlocale(LC_CTYPE, "UTF-8");

        struct winsize windowSize;
        windowSize.ws_row = 24;
        windowSize.ws_col = 80;
        windowSize.ws_xpixel = 0;
        windowSize.ws_ypixel = 0;

        mosh_main(
            strongSelf->_stdinFile,
            strongSelf->_stdoutFile,
            &windowSize,
            &MobileShellMoshStateCallback,
            NULL,
            strongSelf->_host.UTF8String,
            strongSelf->_port.UTF8String,
            strongSelf->_key.UTF8String,
            strongSelf->_predictionMode.UTF8String,
            NULL,
            0,
            strongSelf->_predictOverwrite.length > 0 ? strongSelf->_predictOverwrite.UTF8String : NULL
        );

        if (strongSelf->_readSource) {
            dispatch_source_cancel(strongSelf->_readSource);
            strongSelf->_readSource = nil;
        }
        strongSelf->_started = NO;
        if (strongSelf->_exitHandler) {
            strongSelf->_exitHandler(nil);
        }
    });

    return YES;
}

- (BOOL)sendInput:(NSString *)input
            error:(NSError **)error {
    if (_stdinWriteFD < 0) {
        if (error) {
            *error = [NSError errorWithDomain:MoshClientBridgeErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Mosh bridge input stream is unavailable."}];
        }
        return NO;
    }

    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) {
        return YES;
    }

    ssize_t written = write(_stdinWriteFD, data.bytes, data.length);
    if (written < 0) {
        if (error) {
            *error = [NSError errorWithDomain:MoshClientBridgeErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to write input to the Mosh bridge."}];
        }
        return NO;
    }

    return YES;
}

- (void)closeSession {
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }

    if (_stdinWriteFD >= 0) {
        static const char quitSequence[] = "\x1e.";
        write(_stdinWriteFD, quitSequence, sizeof(quitSequence) - 1);
        close(_stdinWriteFD);
        _stdinWriteFD = -1;
    }

    if (_stdinFile != NULL) {
        fclose(_stdinFile);
        _stdinFile = NULL;
        _stdinReadFD = -1;
    }

    if (_stdoutFile != NULL) {
        fclose(_stdoutFile);
        _stdoutFile = NULL;
        _stdoutWriteFD = -1;
    }

    if (_stdoutReadFD >= 0) {
        close(_stdoutReadFD);
        _stdoutReadFD = -1;
    }
}

@end
