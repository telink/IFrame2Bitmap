//
//  GKSurfaceView.h
//  GKCamara
//
//  Created by 张乐昌 on 17/6/28.
//  Copyright © 2017年 周勇. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIScreen.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>


@interface GKSurfaceView : CAEAGLLayer{
    
    GLint mBackWidth;
    GLint mBackHeight;
    
    EAGLContext* mContext;
    CVOpenGLESTextureRef mLumaTexture;
    CVOpenGLESTextureRef mChromaTexture;
    
    GLuint mHFrameBuffer;
    GLuint mHColorBuffer;
    GLuint mProgram;
    
    const GLfloat* mPreferredConversion;

}
@property (nonatomic, strong) GLKBaseEffect *effect;




// 渲染
@property(nonatomic, assign) CVPixelBufferRef pixelBuffer;
@property(nonatomic, assign) GLuint mProgram;

// 初始化
-(id)initWithFrame:(CGRect)rcFrame;

// 清理缓冲
-(void)resetRenderBuffer;

//绘制为黑色矩形
-(void)drawBlackPixelBuffer;



@end
