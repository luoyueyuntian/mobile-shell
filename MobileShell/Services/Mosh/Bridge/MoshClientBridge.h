#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MoshClientOutputHandler)(NSString *output);
typedef void (^MoshClientExitHandler)(NSString * _Nullable message);

@interface MoshClientBridgeAdapter : NSObject
- (instancetype)init;
- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                         key:(NSString *)key
              predictionMode:(NSString *)predictionMode
           localesBundlePath:(NSString *)localesBundlePath
            predictOverwrite:(NSString * _Nullable)predictOverwrite NS_SWIFT_NAME(init(host:port:key:predictionMode:localesBundlePath:predictOverwrite:));
+ (BOOL)isMoshBinaryLinked;
- (BOOL)startWithOutputHandler:(MoshClientOutputHandler)outputHandler
                   exitHandler:(MoshClientExitHandler)exitHandler
                         error:(NSError **)error NS_SWIFT_NAME(start(outputHandler:exitHandler:));
- (BOOL)sendInput:(NSString *)input
            error:(NSError **)error NS_SWIFT_NAME(send(input:));
- (void)closeSession;
@end

NS_ASSUME_NONNULL_END
