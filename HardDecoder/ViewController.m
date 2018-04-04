//
//  ViewController.m
//  HardDecoder
//
//  Created by 周勇 on 2018/4/3.
//  Copyright © 2018年 张乐昌. All rights reserved.
//

#import "ViewController.h"
#import "PacketSorter.h"
#import "ParseFrame.h"
#import "VideoPlayer.h"
#import "AudioPlayer.h"
#import "GKSurfaceView.h"
#import "Parameter.h"
#define LOCALFILE(fileName,fileType) ([[NSBundle mainBundle]pathForResource:fileName ofType:fileType])

typedef void (^CVResult)(CVPixelBufferRef ref);
typedef void (^UIResult)(UIImage *img);

@interface ViewController ()<PackSortDelegate>
{
    PacketSorter *_videoSorter;
    PacketSorter *_audioSorter;
    
    VideoPlayer  *_videoPlayer;
    AudioPlayer  *_audioPlayer;
    
    GKSurfaceView *_surfaceView; //图片展示视图
    
    BOOL           _isVideoPlayerActive;
    BOOL           _isAudioPlayerActive;
    
    uint8_t       *_iframeBuffer;
    NSUInteger     _iframeLength;
}

@property (weak, nonatomic) IBOutlet UIImageView *convertImage;

@end

@implementation ViewController


- (void)viewDidLoad {

    _videoSorter = [[PacketSorter alloc]init];
    _audioSorter = [[PacketSorter alloc]init];
    _videoSorter.delegate = self;
    _audioSorter.delegate = self;
    _isVideoPlayerActive = false;
    _isAudioPlayerActive = false;
    [_videoSorter sortFile:LOCALFILE(@"video", @"h264") type:SORTPACKETTYPE_Video];  //模拟获取测试的单帧视频数据
    [_audioSorter sortFile:LOCALFILE(@"audio", @"pcm") type:SORTPACKETTYPE_Audio];   //模拟获取测试的单帧音频数据

    _videoPlayer = [[VideoPlayer alloc]init];
    _audioPlayer = [[AudioPlayer alloc]init];

    // SurfaceView 作为视频解码后的draw控件
    CGRect frame = CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), CGRectGetWidth(self.view.bounds)*480.f/720);
    _surfaceView = [[GKSurfaceView alloc] initWithFrame:frame];
    [self.view.layer addSublayer:_surfaceView];
    [super viewDidLoad];
    
   

    NSData *idata = [NSData dataWithContentsOfFile:LOCALFILE(@"iframe", @"h264")];
    _iframeBuffer = (uint8_t *)malloc(idata.length+4);
    memset(_iframeBuffer, 0, idata.length+4);
    memcpy(_iframeBuffer, idata.bytes, idata.length);
    memcpy(_iframeBuffer+idata.length, KStartCode, 4);
    _iframeLength = idata.length;

}

-(void)sortPackData:(VideoPacket *)pack type:(SORTPACKETTYPE)type
{
    if (type == SORTPACKETTYPE_Video) {
        if (_isVideoPlayerActive) {
            [self playOneVideo:pack];
        }
    }else if(type == SORTPACKETTYPE_Audio){
        if (_isAudioPlayerActive) {
            [self playOneAudio:pack];
        }
    }
}

-(void)playOneVideo:(VideoPacket*)pack{
    [self convertFrame:pack.buffer length:pack.size result:^(CVPixelBufferRef ref) {
        if(ref){
            dispatch_sync(dispatch_get_main_queue(), ^{
                [_surfaceView setPixelBuffer:ref];
                CVPixelBufferRelease(ref);
            });
        }
    }];
}

-(void)convertFrame:(uint8_t *)frame length:(NSUInteger)length result:(CVResult)result
{
    // 添加到链表
    VideoPacket *vp = nil;
    ParseFrame* parseFrame = [[ParseFrame alloc] init];
    [parseFrame init:frame len:(int)length];
    while(YES){
        vp = [parseFrame GetNextNalu];
        if(vp == NULL) break;
        CVPixelBufferRef pixelBuffer = [_videoPlayer decode2Surface:vp];
        result(pixelBuffer);
    }
    [parseFrame uint];
}



-(void)convertIframe2Image:(uint8_t *)iframe length:(NSUInteger)length result:(UIResult)result
{
    [self convertFrame:iframe length:length result:^(CVPixelBufferRef ref) {
        if(ref){
            CVPixelBufferLockBaseAddress(ref, 0);
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:ref];
            CVPixelBufferUnlockBaseAddress(ref, 0);
            CIContext *temporaryContext = [CIContext contextWithOptions:nil];
            CGImageRef videoImage = [temporaryContext
                                     createCGImage:ciImage
                                     fromRect:CGRectMake(0, 0,
                                                         CVPixelBufferGetWidth(ref),
                                                         CVPixelBufferGetHeight(ref))];
            UIImage *uiImage = [UIImage imageWithCGImage:videoImage];
            CGImageRelease(videoImage);
            CVPixelBufferRelease(ref);
            result(uiImage);
        }
    }];
}


/**
 关键帧转位图

 @param sender sender
 */
- (IBAction)Iframe2Bitmap:(id)sender {
    [self convertIframe2Image:_iframeBuffer length:_iframeLength result:^(UIImage *img) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.convertImage.image = img;
        });
    }];
}

-(void)playOneAudio:(VideoPacket *)pack{
    [_audioPlayer play:pack.buffer length:(unsigned int)pack.size];
}

- (IBAction)playH264:(UIButton *)sender {
    _isVideoPlayerActive = !_isVideoPlayerActive;
 
}
- (IBAction)playAac:(id)sender {
    _isAudioPlayerActive = !_isAudioPlayerActive;
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
     self.convertImage.image = nil;
}






@end
