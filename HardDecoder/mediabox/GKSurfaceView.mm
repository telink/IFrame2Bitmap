//
//  GKSurfaceView.m
//  GKCamara
//
//  Created by 周勇 on 17/6/28.
//  Copyright © 2017年 周勇. All rights reserved.
//

#import "GKSurfaceView.h"


enum UNIFORM{

    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};

enum ATTRIB{
    
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

GLint uniforms[NUM_UNIFORMS];

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

@implementation GKSurfaceView

@synthesize pixelBuffer = _pixelBuffer;
@synthesize mProgram;

-(CVPixelBufferRef)pixelBuffer{
    return _pixelBuffer;
}

- (void)setPixelBuffer:(CVPixelBufferRef)pb
{
    if(_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    _pixelBuffer = CVPixelBufferRetain(pb);
    
    int frameWidth = (int)CVPixelBufferGetWidth(_pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(_pixelBuffer);
    [self displayPixelBuffer:_pixelBuffer width:frameWidth height:frameHeight];
}

-(id)initWithFrame:(CGRect)rcFrame{
    
    self = [super init];
    if(self){
        
        CGFloat scale = [[UIScreen mainScreen] scale];
        self.contentsScale = scale;
        
        self.opaque = TRUE;
        self.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:YES]};
        
        [self setFrame:rcFrame];
        mContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!mContext) {
            return nil;
        }
        
        mPreferredConversion = kColorConversion709;
        [self setupGL];
    }
    
    return self;
}

- (void) releaseBuffers
{
    if(mHFrameBuffer) {
        glDeleteFramebuffers(1, &mHFrameBuffer);
        mHFrameBuffer = 0;
    }
    
    if(mHColorBuffer) {
        glDeleteRenderbuffers(1, &mHColorBuffer);
        mHColorBuffer = 0;
    }
}

-(void)resetRenderBuffer{
    if (!mContext || ![EAGLContext setCurrentContext:mContext]) {
        return;
    }
    
    [self releaseBuffers];
    [self createBuffers];
}

-(GLKBaseEffect *)effect
{
    if (_effect) {
        _effect = [[GLKBaseEffect alloc] init];
    }
    return _effect;
}

-(void)drawBlackPixelBuffer;
{
//    [self resetRenderBuffer];
    //draw frame
    [self drawFrame];
}

- (void)tearDownBuffers
{
    if (mHFrameBuffer) {
        //delete framebuffer
        glDeleteFramebuffers(1, &mHFrameBuffer);
        mHFrameBuffer = 0;
    }
}


- (void)drawFrame {
    //bind framebuffer & set viewport
    glBindFramebuffer(GL_FRAMEBUFFER, mHFrameBuffer);
    glViewport(0, 0, mBackWidth, mBackWidth);
    
    //bind shader program
    [self.effect prepareToDraw];
    
    //clear the screen
    glClear(GL_COLOR_BUFFER_BIT); glClearColor(0.0, 0.0, 0.0, 1.0);
    
    //set up vertices
    GLfloat vertices[] = {
        -0.5f, -0.5f, -1.0f, 0.0f, 0.5f, -1.0f, 0.5f, -0.5f, -1.0f,
    };
    
    //set up colors
    GLfloat colors[] = {
        0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,
    };
    //draw triangle
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 0, vertices);
    glVertexAttribPointer(GLKVertexAttribColor,4, GL_FLOAT, GL_FALSE, 0, colors);
//    glDrawArrays(GL_TRIANGLES, 0, 3);
    
    //present render buffer
    glBindRenderbuffer(GL_RENDERBUFFER, mHColorBuffer);
    if ([mContext presentRenderbuffer:GL_RENDERBUFFER]) {
        NSLog(@"presentRenderBuffer success...");
    }
}



- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer width:(uint32_t)frameWidth height:(uint32_t)frameHeight
{
    if (!mContext || ![EAGLContext setCurrentContext:mContext]) {
        return;
    }
    
    if(pixelBuffer == NULL) {
        NSLog(@"Pixel buffer is null");
        return;
    }
    
    CVReturn err;
    
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    /*
     Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
     */
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    
    if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
        mPreferredConversion = kColorConversion601;
    }
    else {
        mPreferredConversion = kColorConversion709;
    }
    
    /*
     CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef.
     */
    
    /*
     Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
     */
    
    CVOpenGLESTextureCacheRef _videoTextureCache;
    
    // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
    err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, mContext, NULL, &_videoTextureCache);
    if (err != noErr) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
    
    glActiveTexture(GL_TEXTURE0);
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       frameWidth,
                                                       frameHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &mLumaTexture);
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(mLumaTexture), CVOpenGLESTextureGetName(mLumaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    if(planeCount == 2) {
        // UV-plane.
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &mChromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(mChromaTexture), CVOpenGLESTextureGetName(mChromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, mHFrameBuffer);
    
    // Set the view port to the entire view.
    glViewport(0, 0, mBackWidth, mBackHeight);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Use shader program.
    glUseProgram(self.mProgram);
    //    glUniform1f(uniforms[UNIFORM_LUMA_THRESHOLD], 1);
    //    glUniform1f(uniforms[UNIFORM_CHROMA_THRESHOLD], 1);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, mPreferredConversion);
    
    // Set up the quad vertices with respect to the orientation and aspect ratio of the video.
    CGRect viewBounds = self.bounds;
    CGSize contentSize = CGSizeMake(frameWidth, frameHeight);
    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(contentSize, viewBounds);
    
    // Compute normalized quad coordinates to draw the frame into.
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/viewBounds.size.width,
                                        vertexSamplingRect.size.height/viewBounds.size.height);
    
    // Normalize the quad vertices.
    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = 1.0;//cropScaleAmount.height/cropScaleAmount.width;
    }
    else {
        normalizedSamplingSize.width = 1.0;//cropScaleAmount.width/cropScaleAmount.height;
        normalizedSamplingSize.height = 1.0;;
    }
    
    /*
     The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
     Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively, covers the entire screen.
     */
    GLfloat quadVertexData [] = {
        static_cast<GLfloat>(-1 * normalizedSamplingSize.width), static_cast<GLfloat>(-1 * normalizedSamplingSize.height),static_cast<GLfloat>(normalizedSamplingSize.width), static_cast<GLfloat>(-1 * normalizedSamplingSize.height),
        static_cast<GLfloat>(-1 * normalizedSamplingSize.width), static_cast<GLfloat>(normalizedSamplingSize.height),
        static_cast<GLfloat>(normalizedSamplingSize.width), static_cast<GLfloat>(normalizedSamplingSize.height),
    };
    
    // Update attribute values.
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    /*
     The texture vertices are set up such that we flip the texture vertically. This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system.
     */
    CGRect textureSamplingRect = CGRectMake(0, 0, 1, 1);
    GLfloat quadTextureData[] =  {
        static_cast<GLfloat>(CGRectGetMinX(textureSamplingRect)), static_cast<GLfloat>(CGRectGetMaxY(textureSamplingRect)),
        static_cast<GLfloat>(CGRectGetMaxX(textureSamplingRect)), static_cast<GLfloat>(CGRectGetMaxY(textureSamplingRect)),
        static_cast<GLfloat>(CGRectGetMinX(textureSamplingRect)), static_cast<GLfloat>(CGRectGetMinY(textureSamplingRect)),
        static_cast<GLfloat>(CGRectGetMaxX(textureSamplingRect)), static_cast<GLfloat>(CGRectGetMinY(textureSamplingRect))
    };
    
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, mHColorBuffer);
    [mContext presentRenderbuffer:GL_RENDERBUFFER];
    
    [self cleanUpTextures];
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    
    if(_videoTextureCache) {
        CFRelease(_videoTextureCache);
    }
}

// OpenGl ES
- (void) createBuffers
{
    glGenFramebuffers(1, &mHFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, mHFrameBuffer);
    
    glGenRenderbuffers(1, &mHColorBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, mHColorBuffer);
    
    [mContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &mBackWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &mBackHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, mHColorBuffer);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)setupBuffers
{
    glDisable(GL_DEPTH_TEST);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    
    [self createBuffers];
}

- (void)setupGL
{
    if (!mContext || ![EAGLContext setCurrentContext:mContext]) {
        return;
    }
    
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.mProgram);
    
    // 0 and 1 are the texture IDs of _lumaTexture and _chromaTexture respectively.
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, mPreferredConversion);
}

- (void) cleanUpTextures
{
    if (mLumaTexture) {
        CFRelease(mLumaTexture);
        mLumaTexture = NULL;
    }
    
    if (mChromaTexture) {
        CFRelease(mChromaTexture);
        mChromaTexture = NULL;
    }
}

const GLchar *shader_fsh = (const GLchar*)"varying highp vec2 texCoordVarying;"
"precision mediump float;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerUV;"
"uniform mat3 colorConversionMatrix;"
"void main()"
"{"
"    mediump vec3 yuv;"
"    lowp vec3 rgb;"
//   Subtract constants to map the video range start at 0
"    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));"
"    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));"
"    rgb = colorConversionMatrix * yuv;"
"    gl_FragColor = vec4(rgb, 1);"
"}";

const GLchar *shader_vsh = (const GLchar*)"attribute vec4 position;"
"attribute vec2 texCoord;"
"uniform float preferredRotation;"
"varying vec2 texCoordVarying;"
"void main()"
"{"
"    mat4 rotationMatrix = mat4(cos(preferredRotation), -sin(preferredRotation), 0.0, 0.0,"
"                               sin(preferredRotation),  cos(preferredRotation), 0.0, 0.0,"
"                               0.0,					    0.0, 1.0, 0.0,"
"                               0.0,					    0.0, 0.0, 1.0);"
"    gl_Position = position * rotationMatrix;"
"    texCoordVarying = texCoord;"
"}";

- (BOOL)loadShaders
{
    GLuint vertShader = 0, fragShader = 0;
    
    // Create the shader program.
    self.mProgram = glCreateProgram();
    
    if(![self compileShaderString:&vertShader type:GL_VERTEX_SHADER shaderString:shader_vsh]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    if(![self compileShaderString:&fragShader type:GL_FRAGMENT_SHADER shaderString:shader_fsh]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(self.mProgram, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(self.mProgram, fragShader);
    
    // Bind attribute locations. This needs to be done prior to linking.
    glBindAttribLocation(self.mProgram, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.mProgram, ATTRIB_TEXCOORD, "texCoord");
    
    // Link the program.
    if (![self linkProgram:self.mProgram]) {
        NSLog(@"Failed to link program: %d", self.mProgram);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (self.mProgram) {
            glDeleteProgram(self.mProgram);
            self.mProgram = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.mProgram, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.mProgram, "SamplerUV");
    
    //    uniforms[UNIFORM_LUMA_THRESHOLD] = glGetUniformLocation(self.program, "lumaThreshold");
    //    uniforms[UNIFORM_CHROMA_THRESHOLD] = glGetUniformLocation(self.program, "chromaThreshold");
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.mProgram, "preferredRotation");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.mProgram, "colorConversionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(self.mProgram, vertShader);
        glDeleteShader(vertShader);
    }
    
    if (fragShader) {
        glDetachShader(self.mProgram, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShaderString:(GLuint *)shader type:(GLenum)type shaderString:(const GLchar*)shaderString
{
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &shaderString, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    GLint status = 0;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
    const GLchar *source = (GLchar *)[sourceString UTF8String];
    
    return [self compileShaderString:shader type:type shaderString:source];
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (void)dealloc
{
    if (mHFrameBuffer) {
        glDeleteFramebuffers(1, &mHFrameBuffer);
        mHFrameBuffer = 0;
    }
    
    if (!mContext || ![EAGLContext setCurrentContext:mContext]) {
        return;
    }
    
    [self cleanUpTextures];
    
    if(_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    if (self.mProgram) {
        glDeleteProgram(self.mProgram);
        self.mProgram = 0;
    }
    if(mContext) {
        mContext = nil;
    }
}

@end
