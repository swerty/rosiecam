//
//  RAViewController.m
//  RosieApp
//
//  Created by Sean Wertheim on 2/22/14.
//  Copyright (c) 2014 Sean Wertheim. All rights reserved.
//

#import "RAViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

typedef enum {
    RARecordingStateUnknown,
    RARecordingStateRecording,
    RARecordingStateFinishedRecording
} RARecordingState;

@interface RAViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign) RARecordingState recordingState;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic) dispatch_queue_t assetWritingQueue;
@property (nonatomic, assign) BOOL videoInputReady;
@property (nonatomic, strong) AVAssetWriterInput *assetWriterVideoInput;

@end

@implementation RAViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    NSLog(@"RARecordingingStateFinishedRecording: %d", RARecordingStateFinishedRecording);
    
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice;
    for (AVCaptureDevice *device in devices){
        if([device position] == AVCaptureDevicePositionFront){
            captureDevice = device;
        }
    }
    AVCaptureDeviceInput *videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:nil];
    [self.captureSession addInput:videoInput];
    
    //create preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];
    
    //create output
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:NO];
    [videoDataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id) kCVPixelBufferPixelFormatTypeKey]];
    dispatch_queue_t videoDataDispatchQueue = dispatch_queue_create("edu.CS2049.videoDataOutputQueue", DISPATCH_QUEUE_SERIAL); //instantiates new queue
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataDispatchQueue];
    
    //add output
    [self.captureSession addOutput:videoDataOutput];
    
    //assemble the file url
    NSString *fileName = @"temp.mp4";
    NSError *error = nil;
    self.fileURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject]URLByAppendingPathComponent:fileName];
    
    //remove the file from the path of the file URL if there's a file there
    if([[NSFileManager defaultManager] fileExistsAtPath:self.fileURL.path]){
        [[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:&error];
    }
    
    //instantiate the asset writer
    NSError *assetWriterError = nil;
    self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.fileURL fileType:AVFileTypeQuickTimeMovie error:&assetWriterError];
    
    if (assetWriterError) {
        NSLog(@"Therewas an error instantiating the asserwriter %@", assetWriterError);
    } else {
        NSLog(@"asser writer instantiated");
    }
    
    //instantiate a queue for asset writing so we have access to it later in sample buffer method
    self.assetWritingQueue = dispatch_queue_create("edu.cornell.myUniqueQueueName", DISPATCH_QUEUE_SERIAL);
    
    [self.captureSession startRunning];
}
                                       
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
        NSLog(@"got sample buffer");
    
    if(!self.videoInputReady){
        self.videoInputReady = [self setUpVideoInput:CMSampleBufferGetFormatDescription(sampleBuffer)];
    }
    

    
    if (self.assetWriter && (self.recordingState == RARecordingStateRecording)) {
        NSLog(@"we should do something with this sample buffer");
        
        CFRetain(sampleBuffer);
        
        dispatch_async(self.assetWritingQueue, ^{
            
            
        if(self.assetWriter.status == AVAssetWriterStatusUnknown){ //first frame
                
            
            if (self.videoInputReady) {
                if([self.assetWriter startWriting]){
                    CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                    [self.assetWriter startSessionAtSourceTime:startTime];
                }
            }
        }
        else if (self.assetWriter.status == AVAssetWriterStatusWriting) {
            if (self.assetWriterVideoInput.isReadyForMoreMediaData) {
                NSLog(@"appending sample buffer");
                [self.assetWriterVideoInput appendSampleBuffer:sampleBuffer];
            }
        }
        
            
        CFRelease(sampleBuffer);
        
        });
    }
                       
}

- (BOOL) setUpVideoInput:(CMFormatDescriptionRef)formatDescription{
    
    CMVideoDimensions videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    
    
    float bitsPerPixel;
    
    int numPixels = videoDimensions.width * videoDimensions.height;
    int bitsPerSecond;
    
    // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
    if ( numPixels < (640 * 480) )
        bitsPerPixel = 4.05; // This bitrate matches the quality produced by AVCaptureSessionPresetMedium or Low.
    else
        bitsPerPixel = 11.4; // This bitrate matches the quality produced by AVCaptureSessionPresetHigh.
    
    bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *videoCompressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                              AVVideoCodecH264, AVVideoCodecKey,
                                              [NSNumber numberWithInteger:videoDimensions.width], AVVideoWidthKey,
                                              [NSNumber numberWithInteger:videoDimensions.height], AVVideoHeightKey,
                                              [NSDictionary dictionaryWithObjectsAndKeys:
                                               [NSNumber numberWithInteger:bitsPerSecond], AVVideoAverageBitRateKey,
                                               [NSNumber numberWithInteger:30], AVVideoMaxKeyFrameIntervalKey,
                                               nil], AVVideoCompressionPropertiesKey,
                                              nil];
    
    self.assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
    
    if([self.assetWriter canAddInput:self.assetWriterVideoInput]){
        [self.assetWriter addInput:self.assetWriterVideoInput];
        return YES;
    } else {
        NSLog(@"COULD NOT ADD ASSET WRITER VIDEO INPUT");
    }
    
    return NO;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)startButtonPressed:(id)sender {
    NSLog(@"start button pressed");
    
    self.recordingState = RARecordingStateRecording;
}

- (IBAction)stopButtonPressed:(id)sender {
    NSLog(@"stop button pressed");
    
    //stop the session and remove the preview layer
    [self.captureSession stopRunning];
    [self.previewLayer removeFromSuperlayer];
    
    //finish asset writing
    [self.assetWriter finishWritingWithCompletionHandler:^{
        NSLog(@"finished writing");
    }];
    [self.assetWriterVideoInput markAsFinished];
    
    self.recordingState = RARecordingStateFinishedRecording;
}

- (IBAction)playButtonPressed:(id)sender {
    NSLog(@"play button pressed");
    
    MPMoviePlayerViewController *moviePlayerViewController = [[MPMoviePlayerViewController alloc] initWithContentURL:self.fileURL];
    [self presentMoviePlayerViewControllerAnimated:moviePlayerViewController];
    [moviePlayerViewController.moviePlayer play];
}

@end
