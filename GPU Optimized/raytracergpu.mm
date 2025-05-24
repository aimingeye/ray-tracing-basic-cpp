#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#include <vector>
#include <iostream>
#include <fstream>

// Matching structures with Metal shader
struct Sphere {
    simd_float3 center;
    float radius;
    float radius2;
    simd_float3 surfaceColor;
    simd_float3 emissionColor;
    float transparency;
    float reflection;
};

struct Camera {
    float invWidth;
    float invHeight;
    float angle;
    float aspectratio;
};

@interface MetalRenderer : NSObject
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLComputePipelineState> computePipelineState;
@property (nonatomic, strong) id<MTLBuffer> outputBuffer;
@property (nonatomic, strong) id<MTLBuffer> spheresBuffer;
@end

@implementation MetalRenderer

- (instancetype)initWithWidth:(unsigned)width height:(unsigned)height {
    if (self = [super init]) {
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            NSLog(@"Metal is not supported on this device");
            return nil;
        }
        
        _commandQueue = [_device newCommandQueue];
        
        // Load metal library
        NSError *error = nil;
        NSURL *libraryURL = [NSURL fileURLWithPath:@"Raytracer.metallib"];
        id<MTLLibrary> library = [_device newLibraryWithURL:libraryURL error:&error];
        if (!library) {
            NSLog(@"Failed to load Metal library: %@", error);
            return nil;
        }
        
        id<MTLFunction> kernel = [library newFunctionWithName:@"raytracerKernel"];
        _computePipelineState = [_device newComputePipelineStateWithFunction:kernel error:&error];
        if (!_computePipelineState) {
            NSLog(@"Failed to create compute pipeline state: %@", error);
            return nil;
        }
        
        // Create output buffer
        _outputBuffer = [_device newBufferWithLength:width * height * sizeof(simd_float3) 
                                           options:MTLResourceStorageModeShared];
    }
    return self;
}

- (void)renderWithSpheres:(const std::vector<Sphere>&)spheres width:(unsigned)width height:(unsigned)height {
    // Create and fill spheres buffer
    _spheresBuffer = [_device newBufferWithBytes:spheres.data() 
                                        length:spheres.size() * sizeof(Sphere) 
                                       options:MTLResourceStorageModeShared];
    
    // Setup camera
    Camera camera;
    camera.invWidth = 1.0f / width;
    camera.invHeight = 1.0f / height;
    camera.angle = tanf(M_PI * 0.5f * 30.0f / 180.0f);
    camera.aspectratio = (float)width / (float)height;
    
    // Create command buffer and encoder
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    
    [computeEncoder setComputePipelineState:_computePipelineState];
    [computeEncoder setBuffer:_outputBuffer offset:0 atIndex:0];
    [computeEncoder setBuffer:_spheresBuffer offset:0 atIndex:1];
    
    int sphereCount = (int)spheres.size();
    [computeEncoder setBytes:&sphereCount length:sizeof(int) atIndex:2];
    [computeEncoder setBytes:&camera length:sizeof(Camera) atIndex:3];
    
    // Calculate grid size
    MTLSize gridSize = MTLSizeMake(width, height, 1);
    MTLSize threadGroupSize = MTLSizeMake(16, 16, 1);
    
    [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroupSize];
    [computeEncoder endEncoding];
    
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    
    // Save the result
    simd_float3* outputData = (simd_float3*)_outputBuffer.contents;
    std::ofstream ofs("./untitled.ppm", std::ios::out | std::ios::binary);
    ofs << "P6\n" << width << " " << height << "\n255\n";
    
    for (unsigned i = 0; i < width * height; ++i) {
        unsigned char r = static_cast<unsigned char>(std::min(1.0f, outputData[i].x) * 255);
        unsigned char g = static_cast<unsigned char>(std::min(1.0f, outputData[i].y) * 255);
        unsigned char b = static_cast<unsigned char>(std::min(1.0f, outputData[i].z) * 255);
        ofs.write(reinterpret_cast<char*>(&r), 1);
        ofs.write(reinterpret_cast<char*>(&g), 1);
        ofs.write(reinterpret_cast<char*>(&b), 1);
    }
    
    ofs.close();
}

@end

int main(int argc, char **argv) {
    unsigned width = 6400, height = 4800;
    
    // Create scene
    std::vector<Sphere> spheres;
    float scale = 10.0f;
    int gridN = 18;
    float radius = 1.2f * scale;
    float cubeSize = 10.0f * scale;
    
    // Create spheres
    for (int n = 0; n < gridN; ++n) {
        int plane = rand() % 3;
        float x = ((float)rand() / RAND_MAX - 0.5f) * cubeSize;
        float y = ((float)rand() / RAND_MAX - 0.5f) * cubeSize;
        float z = ((float)rand() / RAND_MAX - 0.5f) * cubeSize;
        if (plane == 0) z = 0;
        else if (plane == 1) x = 0;
        else y = 0;
        
        Sphere sphere;
        sphere.center = simd_make_float3(x, y, z - 30.0f);  // Moved closer to camera
        sphere.radius = radius;
        sphere.radius2 = radius * radius;
        sphere.surfaceColor = simd_make_float3(0.5f + 0.5f * sin(n * 1.2f),
                                             0.5f + 0.5f * sin(n * 1.5f),
                                             0.5f + 0.5f * sin(n * 0.7f));
        sphere.emissionColor = simd_make_float3(0, 0, 0);
        sphere.transparency = 0.3f;
        sphere.reflection = 0.5f;  // Reduced reflection for better visibility
        spheres.push_back(sphere);
    }
    
    // Add light
    Sphere light;
    light.center = simd_make_float3(0.0f, 20.0f, -15.0f);  // Moved closer
    light.radius = 3.0f;
    light.radius2 = 9.0f;
    light.surfaceColor = simd_make_float3(0.0f, 0.0f, 0.0f);
    light.emissionColor = simd_make_float3(15.0f, 15.0f, 15.0f);  // Increased brightness
    light.transparency = 0.0f;
    light.reflection = 0.0f;
    spheres.push_back(light);
    
    // Create and run renderer
    @autoreleasepool {
        MetalRenderer *renderer = [[MetalRenderer alloc] initWithWidth:width height:height];
        if (renderer) {
            [renderer renderWithSpheres:spheres width:width height:height];
            NSLog(@"Rendering completed");
        } else {
            NSLog(@"Failed to create renderer");
            return 1;
        }
    }
    
    return 0;
}
