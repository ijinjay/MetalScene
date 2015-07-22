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

@implementation GameViewController
{
    // view
    MTKView *_view;
    
    // renderer
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;
    id <MTLLibrary> _defaultLibrary;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    
    AVCaptureVideoDataOutput *_videoData;
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self _setupMetal];
    [self _setupView];
}

- (void)_setupView
{
    _view = (MTKView *)self.view;
    
    // Setup the render target, choose values based on your app
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    _view.paused = YES;
    _view.enableSetNeedsDisplay = NO;
    
}

- (void)_setupMetal
{
    // Set the view to use the default device
    _device = MTLCreateSystemDefaultDevice();
    
    // Create a new command queue
    _commandQueue = [_device newCommandQueue];
    
    // Load all the shader files with a metal file extension in the project
    _defaultLibrary = [_device newDefaultLibrary];
}




@end

