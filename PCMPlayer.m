//
//  PCMPlayer.m
//  Created by chenxianming on 2018/4/19.
//

#import "PCMPlayer.h"

#define kPCMPlayerTag @"PCMPlayer"
#define MIN_SIZE_PER_FRAME 10000
#define QUEUE_BUFFER_SIZE 3      //队列缓冲个数

typedef NS_ENUM(NSUInteger, PCMPlayerState)
{
    PCMPlayerState_Idle,
    PCMPlayerState_Playing,
    PCMPlayerState_Stop,
};

@interface PCMPlayer() {
    AudioQueueRef audioQueue;                                 //音频播放队列
    AudioStreamBasicDescription _audioDescription;
    AudioQueueBufferRef audioQueueBuffers[QUEUE_BUFFER_SIZE]; //音频缓存
    OSStatus osState;
}

@property (nonatomic, assign) PCMPlayerState state;
@property (nonatomic, assign) int64_t currentPlayingId;
@property (nonatomic, assign) NSUInteger dataLength;
@property (nonatomic, assign) NSUInteger currentOffset;
@property (nonatomic, assign) Byte *dataWithByte;
@property (nonatomic, assign) AudioQueueBufferRef lastPlayBufferRef;
@property (nonatomic, assign) AudioQueueBufferRef endPlayBuffferRef;
@property (copy, nonatomic) PCMPlayFinishBlock finishBlock;
@end


@implementation PCMPlayer


- (instancetype)init
{
    self = [super init];
    if (self) {
        
        // 播放PCM使用
        if (_audioDescription.mSampleRate <= 0) {
            //设置音频参数
            _audioDescription.mSampleRate = 16000.0;//采样率
            _audioDescription.mFormatID = kAudioFormatLinearPCM;
            // 下面这个是保存音频数据的方式的说明，如可以根据大端字节序或小端字节序，浮点数或整数以及不同体位去保存数据
            _audioDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            //1单声道 2双声道
            _audioDescription.mChannelsPerFrame = 1;
            //每一个packet一侦数据,每个数据包下的桢数，即每个数据包里面有多少桢
            _audioDescription.mFramesPerPacket = 1;
            //每个采样点16bit量化 语音每采样点占用位数
            _audioDescription.mBitsPerChannel = 16;
            _audioDescription.mBytesPerFrame = (_audioDescription.mBitsPerChannel / 8) * _audioDescription.mChannelsPerFrame;
            //每个数据包的bytes总数，每桢的bytes数*每个数据包的桢数
            _audioDescription.mBytesPerPacket = _audioDescription.mBytesPerFrame * _audioDescription.mFramesPerPacket;
        }
        
        // 使用player的内部线程播放 新建输出
        AudioQueueNewOutput(&_audioDescription, AudioPlayerAQInputCallback, (__bridge void * _Nullable)(self), nil, 0, 0, &audioQueue);
        
        // 设置音量
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
        
        // 初始化需要的缓冲区
        for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
            osState = AudioQueueAllocateBuffer(audioQueue, MIN_SIZE_PER_FRAME, &audioQueueBuffers[i]);
        }
        
        _currentPlayingId = 0;
        _state = PCMPlayerState_Idle;
        
        AudioQueueStart(audioQueue, nil);
        
    }
    return self;
}


- (void)getDataWithBuffer:(AudioQueueBufferRef)buffer isEnd:(BOOL *)isEnd
{
    NSUInteger remainLength = self.dataLength - self.currentOffset;
    
    if (remainLength == 0)
    {
        return;
    }
    
    if (MIN_SIZE_PER_FRAME >= remainLength)
    {
        memset(buffer->mAudioData, 0, sizeof(buffer->mAudioData));
        memcpy(buffer->mAudioData, self.dataWithByte + self.currentOffset, remainLength);
        
        self.currentOffset += remainLength;
        buffer->mAudioDataByteSize =  (unsigned int)remainLength;
        *isEnd = YES;
        self.endPlayBuffferRef = buffer;
        self.lastPlayBufferRef = buffer;
    }
    else
    {
        memset(buffer->mAudioData, 0, sizeof(buffer->mAudioData));
        memcpy(buffer->mAudioData, self.dataWithByte + self.currentOffset, MIN_SIZE_PER_FRAME);
        self.currentOffset += MIN_SIZE_PER_FRAME;
        buffer->mAudioDataByteSize =  (unsigned int)MIN_SIZE_PER_FRAME;
        self.endPlayBuffferRef = NULL;
        self.lastPlayBufferRef = buffer;
    }
    
}

- (void)playWithData:(NSData *)data
             voiceId:(int64_t)voiceId
         finishBlock:(PCMPlayFinishBlock)finish
{
    self.finishBlock = finish;
    if (self.state == PCMPlayerState_Idle)
    {
        [self _playWithData:data voiceId:voiceId];
    }
    
}

- (void)_resetData
{
    self.state = PCMPlayerState_Idle;
    self.currentPlayingId = 0;
    self.dataLength = 0;
    self.currentOffset = 0;
    if (self.dataWithByte)
    {
        free(self.dataWithByte);
        self.dataWithByte = nil;
    }
    
    self.lastPlayBufferRef = nil;
    self.endPlayBuffferRef = nil;

    self.finishBlock = nil;
}

- (void)stopPlay
{
    if (audioQueue != nil) {
        AudioQueueStop(audioQueue,true);
    }
    self.state = PCMPlayerState_Stop;
    audioQueue = nil;
    
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        //do nothing, wait for all callback complete。
        [self class];
    });
}

- (void)_playWithData:(NSData *)data voiceId:(int64_t)voideId
{
    AudioQueueReset(audioQueue);
    self.state = PCMPlayerState_Playing;
    self.currentPlayingId = voideId;
    NSMutableData *currentPlayingData = [NSMutableData new];
    [currentPlayingData appendData:data];
    // 得到数据
    self.dataLength = currentPlayingData.length;
    self.currentOffset = 0;
    self.dataWithByte = (Byte*)malloc(_dataLength);
    [currentPlayingData getBytes:self.dataWithByte length:self.dataLength];
    
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++)
    {
        BOOL isEnd = NO;
        [self getDataWithBuffer:audioQueueBuffers[i] isEnd:&isEnd];
        if (isEnd)
        {
            break;
        }
        
        AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
    }
}

// ************************** 回调 **********************************
static void AudioPlayerAQInputCallback(void* inUserData,AudioQueueRef audioQueueRef, AudioQueueBufferRef audioQueueBufferRef) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PCMPlayer* player = (__bridge PCMPlayer*)inUserData;
        
        //还没入队完
        if (player.endPlayBuffferRef == NULL && player.state == PCMPlayerState_Playing)
        {
            BOOL isEnd = NO;
            [player getDataWithBuffer:audioQueueBufferRef isEnd:&isEnd];
            AudioQueueEnqueueBuffer(audioQueueRef, audioQueueBufferRef, 0, NULL);
        }
        else
        {
            //所有数据入队完
            if (player.endPlayBuffferRef == audioQueueBufferRef || (player.state == PCMPlayerState_Stop && player.lastPlayBufferRef == audioQueueBufferRef))
            {
                if (player.finishBlock != nil)
                {
                    player.finishBlock(player.currentPlayingId);
                    [player _resetData];
                }
            }
        }
    });
}



// ************************** 内存回收 **********************************

- (void)dealloc {
    if (self.dataWithByte)
    {
        free(self.dataWithByte);
        self.dataWithByte = nil;
    }
}

@end

