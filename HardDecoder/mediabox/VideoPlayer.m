
//
//  HardDecoder.m
//  GKCamara
//
//  Created by 张乐昌 on 17/6/28.
//  Copyright © 2017年 张乐昌. All rights reserved.
//

#import "VideoPlayer.h"

static void doDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}


@implementation VideoPlayer

-(BOOL)initDecoderSps:(uint8_t*)sps spsLen:(size_t)spsLen Pps:(uint8_t*)pps ppsLen:(size_t)ppsLen{
    
    if(mDecoderSession) return YES;
    
    const uint8_t* const setPtParam[2] = {sps, pps};
    const size_t setSizesParam[2] = {spsLen, ppsLen};
    
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, setPtParam, setSizesParam, 4, &mDecoderFormatDesc);
    if(status == noErr){
        
        /*const void* keys[] = {kCVPixelBufferPixelFormatTypeKey};
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange; //YUV420
        const void* values[] = {CFNumberCreate(NULL, kCFNumberSInt32Type, &v)};
        
        CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL,
                                                   NULL);
        VTDecompressionOutputCallbackRecord callbackRecord;
        callbackRecord.decompressionOutputCallback = doDecompress;
        callbackRecord.decompressionOutputRefCon = NULL;
        
        status = VTDecompressionSessionCreate(kCFAllocatorDefault, mDecoderFormatDesc, NULL, attrs, &callbackRecord, &mDecoderSession);*/
        [self resetH264Decoder];
        
        printf("create h264 decoder ok");
    }else{
        printf("create h264 decoder err");
    }
    
    return YES;
}

-(CVPixelBufferRef)decode:(VideoPacket*)vp{
    
    CVPixelBufferRef outputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,(void*)vp.buffer, vp.size,
                                kCFAllocatorNull,NULL, 0, vp.size, 0, &blockBuffer);
    
    if(status == kCMBlockBufferNoErr){
        
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {vp.size};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, mDecoderFormatDesc ,
                                           1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
        if(status == kCMBlockBufferNoErr && sampleBuffer){
            
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            // 解码
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(mDecoderSession, sampleBuffer, flags,
                                            &outputPixelBuffer, &flagOut);
            if(decodeStatus == kVTInvalidSessionErr){
                printf("invalid session");
//                [self resetH264Decoder];
                [self unitDecoder];
            }else if(decodeStatus == kVTVideoDecoderBadDataErr){
                [self unitDecoder];
                printf("decode err");
            }else if(decodeStatus != noErr){
                [self unitDecoder];
                printf("decode other err");
            }
            // NSLog(@"decode ok");
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }

    return outputPixelBuffer; // NULL失败
}

-(void)unitDecoder{
    
    if(mDecoderSession){
        VTDecompressionSessionInvalidate(mDecoderSession);
        CFRelease(mDecoderSession);
        mDecoderSession = NULL;
    }
    
    if(mDecoderFormatDesc){
        CFRelease(mDecoderFormatDesc);
        mDecoderFormatDesc = NULL;
    }
    if (_spsSize) {
        free(_sps);
        _spsSize = 0;
    }
    if (_ppsSize) {
        free(_pps);
        _ppsSize = 0;
    }
    NSLog(@"release decoder ok");
}

-(CVPixelBufferRef)decode2Surface:(VideoPacket *)vp{
    
    uint32_t nalSize = (uint32_t)(vp.size - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    vp.buffer[0] = *(pNalSize + 3);
    vp.buffer[1] = *(pNalSize + 2);
    vp.buffer[2] = *(pNalSize + 1);
    vp.buffer[3] = *(pNalSize);
    
    _pixelBuffer = NULL;
    int nalType = vp.buffer[4] & 0x1F;
    switch (nalType) {
        case 0x05:
            if([self initDecoderSps:_sps spsLen:_spsSize Pps:_pps ppsLen:_ppsSize]) {
                _pixelBuffer = [self decode:vp];
            }
            break;
        case 0x07:
            if (_spsSize) {
                free(_sps);
                _sps = NULL;

            }
            _spsSize = vp.size - 4;
            _sps = (uint8_t*)malloc(_spsSize);
            memcpy(_sps, vp.buffer + 4, _spsSize);
            break;
        case 0x08:
            if (_ppsSize) {
                free(_pps);
                _pps = NULL;
            }
             _ppsSize = vp.size - 4;
            _pps = (uint8_t*)malloc(_ppsSize);
            memcpy(_pps, vp.buffer + 4, _ppsSize);
            break;
            
        default:
            _pixelBuffer = [self decode:vp];
            break;
    }
    return _pixelBuffer;
}

- (void)resetH264Decoder
{
    if(mDecoderSession) {
        VTDecompressionSessionInvalidate(mDecoderSession);
        CFRelease(mDecoderSession);
        mDecoderSession = NULL;
    }
    CFDictionaryRef attrs = NULL;
    const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
    //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
    //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
    uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
    attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = doDecompress;
    callBackRecord.decompressionOutputRefCon = NULL;
    if(VTDecompressionSessionCanAcceptFormatDescription(mDecoderSession, mDecoderFormatDesc))
    {
        NSLog(@"yes");
    }
    
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorSystemDefault,
                                                   mDecoderFormatDesc,
                                                   NULL, attrs,
                                                   &callBackRecord,
                                                   &mDecoderSession);
    CFRelease(attrs);
}

@end
