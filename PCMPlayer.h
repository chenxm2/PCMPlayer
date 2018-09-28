//
//  PCMPlayer.h
//
//  Created by chenxianming on 2018/4/19.
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef void(^PCMPlayFinishBlock)(int64_t voiceId);
@interface PCMPlayer : NSObject

- (void)playWithData:(NSData *)data
             voiceId:(int64_t)voiceId
         finishBlock:(PCMPlayFinishBlock)finish;
- (void)stopPlay;
@end
