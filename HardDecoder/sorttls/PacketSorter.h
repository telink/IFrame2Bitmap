//
//  PacketSortter.h
//  HardDecoder
//
//  Created by 张乐昌 on 2018/4/3.
//  Copyright © 2018年 张乐昌. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "VideoPacket.h"
typedef NS_ENUM(NSInteger, SORTPACKETTYPE){
    
    SORTPACKETTYPE_Video = 1,    // 视频数据
    SORTPACKETTYPE_Audio = 2,    // 音频数据
    
};

@protocol PackSortDelegate <NSObject>

-(void)sortPackData:(VideoPacket *)pack type:(SORTPACKETTYPE)type;

@end



@interface PacketSorter : NSObject

@property(nonatomic,weak)id<PackSortDelegate>delegate;

@property (nonatomic, assign) BOOL closeFileParser;

-(void)sortFile:(NSString *)path type:(SORTPACKETTYPE)type;

-(void)sortFile:(NSString *)path;

@end
