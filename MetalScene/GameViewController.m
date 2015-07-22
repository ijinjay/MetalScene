//
//  GameViewController.m
//  MetalScene
//
//  Created by JinJay on 15/7/22.
//  Copyright © 2015年 JinJay. All rights reserved.
//

#import "GameViewController.h"

@import GLKit;
@import SceneKit;
@import CoreMotion;

@implementation GameViewController {
    // view
    MTKView *_view;
    
    // renderer
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    id <MTLLibrary> _defaultLibrary;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    AVCaptureSession *_captureSession;
    CVMetalTextureCacheRef _videoTextureCache;
    id <MTLTexture> _videoTexture[3];
    
    // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
    // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
    NSUInteger _constantDataBufferIndex;
    dispatch_semaphore_t _inflight_semaphore;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self _setupMetal];
    [self _setupView];
}

- (void)_setupView {
    _view = (MTKView *)self.view;
    
    // Setup the render target, choose values based on your app
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    _view.paused = YES;
    _view.enableSetNeedsDisplay = NO;
    
}

- (void)_setupMetal {
    // Set the view to use the default device
    _device = MTLCreateSystemDefaultDevice();
    
    // Create a new command queue
    _commandQueue = [_device newCommandQueue];
    
    // Load all the shader files with a metal file extension in the project
    _defaultLibrary = [_device newDefaultLibrary];
    
    _constantDataBufferIndex = 0;
    _inflight_semaphore = dispatch_semaphore_create(3);
    
    // setup the depth state
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
}

- (void)_setupVideo {
    CVMetalTextureCacheFlush(_videoTextureCache, 0);
    CVReturn textureCacheError = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_videoTextureCache);
    
    if (textureCacheError) {
        NSLog(@">> ERROR: Couldnt create a texture cache");
        assert(0);
    }
    
    // capture session setting
    _captureSession = [[AVCaptureSession alloc] init];
    [_captureSession beginConfiguration];
    [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];
    
    // back camera
    AVCaptureDevice* videoDevice = nil;
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice* device in devices) {
        if ([device position] == AVCaptureDevicePositionBack) {
            videoDevice = device;
        }
    }
    
    if(videoDevice == nil) {
        videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    // Device input
    NSError *error;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    if (error) {
        NSLog(@">> ERROR: Couldnt create AVCaptureDeviceInput");
        assert(0);
    }
    [_captureSession addInput:deviceInput];
    
    // Create the output for the capture session.
    AVCaptureVideoDataOutput * dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    // Set the color space.
    [dataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread to create the texture in memory and allow Metal to use it for rendering
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_captureSession addOutput:dataOutput];
    [_captureSession commitConfiguration];
    
    // this will trigger capture on its own queue
    [_captureSession startRunning];
}


#pragma AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVReturn error;
    
    CVImageBufferRef sourceImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    size_t width = CVPixelBufferGetWidth(sourceImageBuffer);
    size_t height = CVPixelBufferGetHeight(sourceImageBuffer);
    
    CVMetalTextureRef textureRef;
    error = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _videoTextureCache, sourceImageBuffer, NULL, MTLPixelFormatBGRA8Unorm, width, height, 0, &textureRef);
    
    if (error) {
        NSLog(@">> ERROR: Couldnt create texture from image");
        assert(0);
    }
    
    _videoTexture[_constantDataBufferIndex] = CVMetalTextureGetTexture(textureRef);
    if (!_videoTexture[_constantDataBufferIndex]) {
        NSLog(@">> ERROR: Couldn't get texture from texture ref");
        assert(0);
    }
    
    CVBufferRelease(textureRef);
}

- (void)render {
    
    
    dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
    
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    // create a render command encoder so we can render into something
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    if (renderPassDescriptor) {
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setDepthStencilState:_depthState];
        [renderEncoder setFragmentTexture:_videoTexture[_constantDataBufferIndex] atIndex:1];
        
        [renderEncoder endEncoding];
    }
    
    __block dispatch_semaphore_t block_sema = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        
        // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
        // Signal the semaphore and allow the CPU to proceed and construct the next frame.
        dispatch_semaphore_signal(block_sema);
    }];
    
    // finalize rendering here. this will push the command buffer to the GPU
    [commandBuffer commit];
    
    // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
    // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
    // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
    // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
    _constantDataBufferIndex = (_constantDataBufferIndex + 1) % 3;
}

@end

