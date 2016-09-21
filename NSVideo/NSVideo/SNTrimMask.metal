//
//  SNTrimMask.metal
//  SNTrim
//
//  Created by satoshi on 9/16/16.
//  Copyright © 2016 Satoshi Nakajima. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

kernel void SNTrimMask(texture2d<float,access::read>   inputImage   [[ texture(0) ]],
                       texture2d<float,access::write>  outputImage  [[ texture(1) ]],

                      const uint2 gid [[ thread_position_in_grid ]]) {

    float4 pixel = inputImage.read(gid);
    float4 pixel2 = pixel;
    pixel2.r = pixel.g;
    pixel2.g = pixel.r;
    outputImage.write(pixel2, gid);
}

