Shader "Lacuna/Flyover_Bitmask"
{
    Properties
    {
        //[NoScaleOffset] _Udon_3DJ_Depth ("3DJ Depth", 2D) = "white" {}
        _SobelOffset("Sobel Filter Width", Range(0.5, 2.0)) = 1.0
        _SobelSensitivity("Sobel Filter Sensitivity", Range(0.01, 0.2)) = 0.1
        _VoxelSensitivity ("Voxel Sensitivity", Range(0.25, 4)) = 1.0
        _SampleThreshold ("Sampling Threshold", Range(0, 1)) = 0.1
    }
    SubShader
    {
        Lighting Off
        Blend One Zero

        Pass
        {
            HLSLPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag

            #include "LacunaCG.cginc"

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_3DJ_Depth_TexelSize;

            float _SobelOffset;
            float _SobelSensitivity;
            float _VoxelSensitivity;
            float _SampleThreshold;
            

            /*uint encode (uint x, uint y, uint z)
            {
                x = (x | (x << 16u)) & 0x030000FF;
                x = (x | (x << 8u)) & 0x0300F00F;
                x = (x | (x << 4u)) & 0x030C30C3;
                x = (x | (x << 2u)) & 0x09249249;

                y = (y | (y << 16u)) & 0x030000FF;
                y = (y | (y << 8u)) & 0x0300F00F;
                y = (y | (y << 4u)) & 0x030C30C3;
                y = (y | (y << 2u)) & 0x09249249;

                z = (z | (z << 16u)) & 0x030000FF;
                z = (z | (z << 8u)) & 0x0300F00F;
                z = (z | (z << 4u)) & 0x030C30C3;
                z = (z | (z << 2u)) & 0x09249249;

                return x | (y << 1) | (z << 2);
            }

            void insert (uint n, inout uint low, inout uint high)
            {
                low |= n < 32 ? 1u << n : 0u;
                high |= n >= 32 && n < 64 ? 1u << (n - 32) : 0u;
            }

            float SobelDepth(float ldc, float ldl, float ldr, float ldu, float ldd)
            {
                return abs(ldl - ldc) +
                    abs(ldr - ldc) +
                    abs(ldu - ldc) +
                    abs(ldd - ldc);
            }

            float SobelSampleDepth(Texture2D t, SamplerState s, float2 uv, float3 offset)
            {
                float pixelCenter = t.Sample(s, uv).r;
                float pixelLeft = t.Sample(s, uv - offset.xz).r;
                float pixelRight = t.Sample(s, uv + offset.xz).r;
                float pixelUp = t.Sample(s, uv + offset.zy).r;
                float pixelDown = t.Sample(s, uv - offset.zy).r;

                return SobelDepth(pixelCenter, pixelLeft, pixelRight, pixelUp, pixelDown);
            }*/

            uint4 frag (v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into four 32 bit unsigned integers
                // The first 64 bits are a bitmask representing occupied voxels
                // The last 64 bits are a bitmask representing the direction of visibility for 8 2x2x2 quads
                uint bits_x = 0;
                uint bits_y = 0;
                uint bits_z = 0;
                uint bits_w = 0;

                // The source 3D texture is assumed to be 4x the render texture
                // The dimensions of the render texture must be a power of 2
                // It also must be a cube
                // Getting this wrong would be Very Bad™
                float inv_CustomRenderTexture_TexelSize = (1. / (_CustomRenderTextureWidth * 4));

                float3 offset = float3(_Udon_3DJ_Depth_TexelSize.xy, 0) * _SobelOffset;

                // Now we step through our voxels
                [unroll]
                for (uint x = 0; x < 4; x++)
                    for (uint y = 0; y < 4; y++)
                        for (uint z = 0; z < 4; z++)
                        {
                            float3 sampleTexcoord = IN.localTexcoord.xyz + float3(x - 0.5, y - 0.5, z - 0.5) * inv_CustomRenderTexture_TexelSize;

                            float2 leftTexcoord = float2(1. - sampleTexcoord.z, sampleTexcoord.y) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy;
                            float2 rightTexcoord = sampleTexcoord.zy * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Depth_TexelSize.xy;
                            float2 bottomTexcoord = float2(sampleTexcoord.x, 1. - sampleTexcoord.z) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy;
                            float2 topTexcoord = float2(1. - sampleTexcoord.x, 1. - sampleTexcoord.z) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Depth_TexelSize.xy;
                            float2 frontTexcoord = sampleTexcoord.xy * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Depth_TexelSize.xy;
                            float2 backTexcoord = float2(1. - sampleTexcoord.x, sampleTexcoord.y) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Depth_TexelSize.xy;

                            float left_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, leftTexcoord).r; // -X Left
                            float right_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, rightTexcoord).r; // +X Right
                            float bottom_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, bottomTexcoord).r; // -Y Bottom
                            float top_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, topTexcoord).r; // +Y Top
                            float front_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, frontTexcoord).r; // -Z Front
                            float back_depth_texel = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, backTexcoord).r; // +Z Back

                            float left_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, leftTexcoord, offset); // -X Left
                            float right_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, rightTexcoord, offset); // +X Right
                            float bottom_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, bottomTexcoord, offset); // -Y Bottom
                            float top_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, topTexcoord, offset); // +Y Top
                            float front_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, frontTexcoord, offset); // -Z Front
                            float back_depth_texel_sobel = SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, backTexcoord, offset); // +Z Back

                            bool left_depth_texel_flag = left_depth_texel_sobel < _SobelSensitivity && left_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.x, left_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bool right_depth_texel_flag = right_depth_texel_sobel < _SobelSensitivity && right_depth_texel > _SampleThreshold && distance(sampleTexcoord.x, right_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bool bottom_depth_texel_flag = bottom_depth_texel_sobel < _SobelSensitivity && bottom_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.y, bottom_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bool top_depth_texel_flag = top_depth_texel_sobel < _SobelSensitivity && top_depth_texel > _SampleThreshold && distance(sampleTexcoord.y, top_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bool front_depth_texel_flag = front_depth_texel_sobel < _SobelSensitivity && front_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.z, front_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bool back_depth_texel_flag = back_depth_texel_sobel < _SobelSensitivity && back_depth_texel > _SampleThreshold && distance(sampleTexcoord.z, back_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;

                            uint i = encode(x >> 1, y >> 1, z >> 1) * 8;

                            if (left_depth_texel_flag) insert(i, bits_z, bits_w);
                            if (right_depth_texel_flag) insert(i + 1, bits_z, bits_w);
                            if (bottom_depth_texel_flag) insert(i + 2, bits_z, bits_w);
                            if (top_depth_texel_flag) insert(i + 3, bits_z, bits_w);
                            if (front_depth_texel_flag) insert(i + 4, bits_z, bits_w);
                            if (back_depth_texel_flag) insert(i + 5, bits_z, bits_w);


                            if(left_depth_texel_flag || right_depth_texel_flag || bottom_depth_texel_flag || top_depth_texel_flag || front_depth_texel_flag || back_depth_texel_flag)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }
                
                return uint4(bits_x, bits_y, bits_z, bits_w);
            }
            ENDHLSL
        }
    }
}
