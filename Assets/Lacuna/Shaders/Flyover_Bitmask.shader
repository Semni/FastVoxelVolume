Shader "Lacuna/Flyover_Bitmask"
{
    Properties
    {
        [NoScaleOffset] _Udon_3DJ_Depth("3DJ Depth", 2D) = "white" {}
        _VoxelSensitivity("Voxel Sensitivity", Range(0.5, 4)) = 1.0
        _SampleThreshold("Sampling Threshold", Range(0, 1)) = 0.1
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

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_3DJ_Depth_TexelSize;

            float _VoxelSensitivity;
            float _SampleThreshold;

            uint encode(uint x, uint y, uint z)
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

            void insert(uint n, inout uint low, inout uint high)
            {
                if(n < 32)
                {
                    low = low | 1u << n;
                }
                else if(n < 64)
                {
                    high = high | 1u << (n - 32);
                }
            }

            uint4 frag (v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into four 32 bit unsigned integers
                // The first 64 bits are a bitmask representing occupied voxels
                // The next 48 bits represent a direction-mask for colour sampling on 4 2x2x2 quads
                // The remaining 16 bits remain unused
                uint bits_x = 0;
                uint bits_y = 0;
                uint bits_z = 0;
                uint bits_w = 0;

                // The source 3D texture is assumed to be 4x the render texture
                // The dimensions of the render texture must be a power of 2
                // It also must be a cube
                // Getting this wrong would be Very Bad™
                float inv_CustomRenderTexture_TexelSize = (1. / (_CustomRenderTextureWidth * 4));

                float3 sampleTexcoord;

                float left_depth_texel;
                float right_depth_texel;
                float bottom_depth_texel;
                float top_depth_texel;
                float front_depth_texel;
                float back_depth_texel;

                bool left_depth_texel_flag;
                bool right_depth_texel_flag;
                bool bottom_depth_texel_flag;
                bool top_depth_texel_flag;
                bool front_depth_texel_flag;
                bool back_depth_texel_flag;

                // Now we step through our voxels
                [unroll]
                for(uint x = 0; x < 4; x++)
                    for(uint y = 0; y < 4; y++)
                        for(uint z = 0; z < 4; z++)
                        {
                            sampleTexcoord = IN.localTexcoord.xyz + float3(x, y, z) * inv_CustomRenderTexture_TexelSize;

                            left_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, float2(1. - sampleTexcoord.z, sampleTexcoord.y) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy, 0).r; // -X Left
                            right_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, sampleTexcoord.zy * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Depth_TexelSize.xy).r; // +X Right
                            bottom_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, float2(sampleTexcoord.x, 1. - sampleTexcoord.z) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy).r; // -Y Bottom
                            top_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, float2(1. - sampleTexcoord.x, 1. - sampleTexcoord.z) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Depth_TexelSize.xy).r; // +Y Top
                            front_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, sampleTexcoord.xy * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Depth_TexelSize.xy).r; // -Z Front
                            back_depth_texel = _Udon_3DJ_Depth.Sample(sampler_Udon_3DJ_Depth, float2(1. - sampleTexcoord.x, sampleTexcoord.y) * float2(320, 530) * _Udon_3DJ_Depth_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Depth_TexelSize.xy).r; // +Z Back

                            left_depth_texel_flag = left_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.x, left_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            right_depth_texel_flag = right_depth_texel > _SampleThreshold && distance(sampleTexcoord.x, right_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            bottom_depth_texel_flag = bottom_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.y, bottom_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            top_depth_texel_flag = top_depth_texel > _SampleThreshold && distance(sampleTexcoord.y, top_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            front_depth_texel_flag = front_depth_texel > _SampleThreshold && distance(1. - sampleTexcoord.z, front_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;
                            back_depth_texel_flag = back_depth_texel > _SampleThreshold && distance(sampleTexcoord.z, back_depth_texel) <= inv_CustomRenderTexture_TexelSize * _VoxelSensitivity;

                            if(left_depth_texel_flag || right_depth_texel_flag || bottom_depth_texel_flag || top_depth_texel_flag || front_depth_texel_flag || back_depth_texel_flag)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }

                return uint4(bits_x, bits_y, bits_z, bits_w);
            }
            ENDHLSL
        }
    }
}
