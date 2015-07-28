//
//  AppDelegate.h
//  MetalScene
//
//  Created by JinJay on 15/7/22.
//  Copyright © 2015年 JinJay. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) CMMotionManager *manager;

- (CMMotionManager *)sharedManager;

@end

