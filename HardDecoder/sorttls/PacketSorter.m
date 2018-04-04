//
//  PacketSortter.m
//  HardDecoder
//
//  Created by 张乐昌 on 2018/4/3.
//  Copyright © 2018年 张乐昌. All rights reserved.
//

#import "PacketSorter.h"
#import "VideoFileParser.h"
#import "Parameter.h"

#define MAX_AUDIOSIZE  4096

typedef uint32_t uint32, uint32_be, uint32_le;

@interface PacketSorter()

@property(nonatomic,assign)SORTPACKETTYPE packetType;

@end
@interface PacketSorter()
{
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    uint8_t *_sei;
    NSInteger _seiSize;
    NSString *_fileName;
    NSString *_fileType;
    NSUInteger _curAudioPos;
    
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
}
@property(nonatomic,strong)NSMutableData *srcData;
@property(nonatomic,assign)uint8_t       *audioBuffer;     //音频测试数据
@property(nonatomic,assign)NSUInteger     audioBufferSize;
@end

@implementation PacketSorter

-(NSData *)srcData
{
    if (!_srcData) {
        NSString *path = [[NSBundle mainBundle] pathForResource:_fileName ofType:_fileType];
        _srcData = [NSMutableData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        NSMutableData *data = [NSMutableData dataWithBytes:KStartCode length:4];
        [_srcData appendData:data];
    }
    return _srcData;
}

-(uint8_t *)audioBuffer
{
    if (!_audioBuffer) {
        _audioBuffer = (uint8_t *)self.srcData.bytes;
        _audioBufferSize =self.srcData.length;
    }
    return _audioBuffer;
}



//返回根目录路径 "document"
- (NSString *)getDocumentPath{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = [paths firstObject];
    return documentPath;
}

-(void)sortFile:(NSString *)path type:(SORTPACKETTYPE)type
{
    _packetType = type;
    [self sortFile:path];
}


-(void)sortFile:(NSString *)path
{
    NSAssert(path, @"文件路径为空");
    NSString *fullName = [path componentsSeparatedByString:@"/"].lastObject;
    _fileType = [fullName componentsSeparatedByString:@"."].lastObject;
    _fileName = [fullName componentsSeparatedByString:[NSString stringWithFormat:@".%@",_fileType]].firstObject;
    [self sortFile:_fileName fileExt:_fileType];
}

-(void)sortFile:(NSString*)fileName fileExt:(NSString*)fileExt
{
    _fileName = fileName;
    _fileType = fileExt;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (true) {
            if (_closeFileParser || !self.srcData)
            {
                break;
            }
            if (_packetType == SORTPACKETTYPE_Video)
            {
                [self distributeVideopack];
                
            }else if(_packetType == SORTPACKETTYPE_Audio)
            {
                [self distributeAudiopack];
            }else{
                
                break;
            }
            [NSThread sleepForTimeInterval:0.05];
        }
    });
}
//简单音频数据测试分包
-(void)distributeAudiopack
{
    VideoPacket *vp = [[VideoPacket alloc]initWithSize:MAX_AUDIOSIZE];
    vp.type = SORTPACKETTYPE_Audio;
    memset(vp.buffer, 0, MAX_AUDIOSIZE);
    memcpy(vp.buffer, self.audioBuffer+_curAudioPos, MAX_AUDIOSIZE);
    _curAudioPos += MAX_AUDIOSIZE;
    if (_curAudioPos >= self.srcData.length*0.9) {
        _curAudioPos = 0;
    }
    if ([_delegate respondsToSelector:@selector(sortPackData:type:)]) {
        [_delegate sortPackData:vp type:_packetType];
    }
}


-(void)distributeVideopack
{
    VideoFileParser *parser = [VideoFileParser alloc];
    [parser open:self.srcData];
    VideoPacket *vp = nil;
    while(true)
    {
        if (_closeFileParser) {
            break;
        }
        vp = [parser nextPacket];
        if(vp == nil)
        {
            break;
        }
        [self anlyseFrameVideoPack:vp];
        [NSThread sleepForTimeInterval:0.05];
    }
    [parser close];
    return;
}

-(void)anlyseFrameVideoPack:(VideoPacket *)vp
{
    if (vp.size < 5) {
        return;
    }
    if (!vp.buffer) {
        return;
    }
    if (_packetType == SORTPACKETTYPE_Video)
    {
        FRAMETYPE type;
        int nalType = 0;
        if (memcmp(vp.buffer, KStartCode, 4)) {
            nalType = vp.buffer[3] & 0x1F;
        }else if(memcmp(vp.buffer, KStartSEICode, 3)){
            nalType = vp.buffer[4] & 0x1F;
        }
        switch (nalType)
        {
            case 0x05:
                type = I_FRAME;
                NSLog(@"🍑🍑->I size = %ld",vp.size);
                break;
            case 0x07:
                type = P_FRAME;
                NSLog(@"🍑🍑->SPS = %ld",vp.size);
                break;
            case 0x08:
                type = P_FRAME;
                NSLog(@"🍑🍑->PPS = %ld",vp.size);
                break;
            case 0x06: //SEI
                type = P_FRAME;
                NSLog(@"🍑🍑->SEI = %ld",vp.size);
                break;
            default:
                type = P_FRAME;
                NSLog(@"🍑🍑->P = %ld",vp.size);
                break;
        }
        vp.type = type;
    }
    if ([_delegate respondsToSelector:@selector(sortPackData:type:)]) {
        [_delegate sortPackData:vp type:_packetType];
    }
}

@end



