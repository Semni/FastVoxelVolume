Shader "Lacuna/Flyover_Bitmask"
{
    Properties
    {
        [NoScaleOffset] _Udon_3DJ_Depth ("3DJ Depth", 2D) = "white" {}
        _VoxelSensitivity ("Voxel Sensitivity", Range(0.5, 4)) = 1.0
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

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_3DJ_Depth_TexelSize;

            float _VoxelSensitivity;
            float _SampleThreshold;

            uint encode (uint x, uint y, uint z)
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
                if(n < 32)
                {
                    low = low | 1u << n;
                }
                else if(n < 64)
                {
                    high = high | 1u << (n - 32);
                }
            }

            uint3 frag (v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into four 32 bit unsigned integers
                // The first 64 bits are a bitmask representing occupied voxels
                // The next 32 bits represent a preferred sampling direction for 8 2x2x2 quads
                uint bits_x = 0;
                uint bits_y = 0;
                uint bits_z = 0;

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

                uint left_0;
                uint right_0;
                uint bottom_0;
                uint top_0;
                uint front_0;
                uint back_0;

                uint left_1;
                uint right_1;
                uint bottom_1;
                uint top_1;
                uint front_1;
                uint back_1;

                uint left_2;
                uint right_2;
                uint bottom_2;
                uint top_2;
                uint front_2;
                uint back_2;

                uint left_3;
                uint right_3;
                uint bottom_3;
                uint top_3;
                uint front_3;
                uint back_3;

                uint left_4;
                uint right_4;
                uint bottom_4;
                uint top_4;
                uint front_4;
                uint back_4;

                uint left_5;
                uint right_5;
                uint bottom_5;
                uint top_5;
                uint front_5;
                uint back_5;

                uint left_6;
                uint right_6;
                uint bottom_6;
                uint top_6;
                uint front_6;
                uint back_6;

                uint left_7;
                uint right_7;
                uint bottom_7;
                uint top_7;
                uint front_7;
                uint back_7;

                // Now we step through our voxels
                [unroll]
                for (uint x = 0; x < 4; x++)
                    for (uint y = 0; y < 4; y++)
                        for (uint z = 0; z < 4; z++)
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

                            switch (encode(x >> 1, y >> 1, z >> 1))
                            {
                                case 0: // (0, 0, 0)
                                    left_0 = left_depth_texel_flag ? left_0++ : left_0;
                                    right_0 = right_depth_texel_flag ? right_0++ : right_0;
                                    bottom_0 = bottom_depth_texel_flag ? bottom_0++ : bottom_0;
                                    top_0 = top_depth_texel_flag ? top_0++ : top_0;
                                    front_0 = front_depth_texel_flag ? front_0++ : front_0;
                                    back_0 = back_depth_texel_flag ? back_0++ : back_0;
                                break;
                                case 1: // (1, 0, 0)
                                    left_1 = left_depth_texel_flag ? left_1++ : left_1;
                                    right_1 = right_depth_texel_flag ? right_1++ : right_1;
                                    bottom_1 = bottom_depth_texel_flag ? bottom_1++ : bottom_1;
                                    top_1 = top_depth_texel_flag ? top_1++ : top_1;
                                    front_1 = front_depth_texel_flag ? front_1++ : front_1;
                                    back_1 = back_depth_texel_flag ? back_1++ : back_1;
                                break;
                                case 2: // (0, 1, 0)
                                    left_2 = left_depth_texel_flag ? left_2++ : left_2;
                                    right_2 = right_depth_texel_flag ? right_2++ : right_2;
                                    bottom_2 = bottom_depth_texel_flag ? bottom_2++ : bottom_2;
                                    top_2 = top_depth_texel_flag ? top_2++ : top_2;
                                    front_2 = front_depth_texel_flag ? front_2++ : front_2;
                                    back_2 = back_depth_texel_flag ? back_2++ : back_2;
                                break;
                                case 3: // (1, 1, 0)
                                    left_3 = left_depth_texel_flag ? left_3++ : left_3;
                                    right_3 = right_depth_texel_flag ? right_3++ : right_3;
                                    bottom_3 = bottom_depth_texel_flag ? bottom_3++ : bottom_3;
                                    top_3 = top_depth_texel_flag ? top_3++ : top_3;
                                    front_3 = front_depth_texel_flag ? front_3++ : front_3;
                                    back_3 = back_depth_texel_flag ? back_3++ : back_3;
                                break;
                                case 4: // (0, 0, 1)
                                    left_4 = left_depth_texel_flag ? left_4++ : left_4;
                                    right_4 = right_depth_texel_flag ? right_4++ : right_4;
                                    bottom_4 = bottom_depth_texel_flag ? bottom_4++ : bottom_4;
                                    top_4 = top_depth_texel_flag ? top_4++ : top_4;
                                    front_4 = front_depth_texel_flag ? front_4++ : front_4;
                                    back_4 = back_depth_texel_flag ? back_4++ : back_4;
                                break;
                                case 5: // (1, 0, 1)
                                    left_5 = left_depth_texel_flag ? left_5++ : left_5;
                                    right_5 = right_depth_texel_flag ? right_5++ : right_5;
                                    bottom_5 = bottom_depth_texel_flag ? bottom_5++ : bottom_5;
                                    top_5 = top_depth_texel_flag ? top_5++ : top_5;
                                    front_5 = front_depth_texel_flag ? front_5++ : front_5;
                                    back_5 = back_depth_texel_flag ? back_5++ : back_5;
                                break;
                                case 6: // (0, 1, 1)
                                    left_6 = left_depth_texel_flag ? left_6++ : left_6;
                                    right_6 = right_depth_texel_flag ? right_6++ : right_6;
                                    bottom_6 = bottom_depth_texel_flag ? bottom_6++ : bottom_6;
                                    top_6 = top_depth_texel_flag ? top_6++ : top_6;
                                    front_6 = front_depth_texel_flag ? front_6++ : front_6;
                                    back_6 = back_depth_texel_flag ? back_6++ : back_6;
                                break;
                                case 7: // (1, 1, 1)
                                    left_7 = left_depth_texel_flag ? left_7++ : left_7;
                                    right_7 = right_depth_texel_flag ? right_7++ : right_7;
                                    bottom_7 = bottom_depth_texel_flag ? bottom_7++ : bottom_7;
                                    top_7 = top_depth_texel_flag ? top_7++ : top_7;
                                    front_7 = front_depth_texel_flag ? front_7++ : front_7;
                                    back_7 = back_depth_texel_flag ? back_7++ : back_7;
                                break;
                            }

                            // (0, 0, 0) = 0
                            // (1, 0, 0) = 1
                            // (0, 1, 0) = 2
                            // (0, 0, 1) = 4
                            // (1, 1, 0) = 3
                            // (1, 0, 1) = 5
                            // (0, 1, 1) = 6
                            // (1, 1, 1) = 7

                            if(left_depth_texel_flag || right_depth_texel_flag || bottom_depth_texel_flag || top_depth_texel_flag || front_depth_texel_flag || back_depth_texel_flag)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }

                // 0 Left, 1 Right, 2 Bottom, 3 Top, 4 Front, 5 Back

                uint3 max_vec;
                uint max_dir;
                
                max_vec = max(uint3(left_7, right_7, bottom_7), uint3(top_7, front_7, back_7));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_7  ? 4 :
                          max_dir == left_7   ? 0 :
                          max_dir == right_7  ? 1 :
                          max_dir == back_7   ? 5 :
                          max_dir == top_7    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_6, right_6, bottom_6), uint3(top_6, front_6, back_6));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_6  ? 4 :
                          max_dir == left_6   ? 0 :
                          max_dir == right_6  ? 1 :
                          max_dir == back_6   ? 5 :
                          max_dir == top_6    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_5, right_5, bottom_5), uint3(top_5, front_5, back_5));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_5  ? 4 :
                          max_dir == left_5   ? 0 :
                          max_dir == right_5  ? 1 :
                          max_dir == back_5   ? 5 :
                          max_dir == top_5    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_4, right_4, bottom_4), uint3(top_4, front_4, back_4));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_4  ? 4 :
                          max_dir == left_4   ? 0 :
                          max_dir == right_4  ? 1 :
                          max_dir == back_4   ? 5 :
                          max_dir == top_4    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_3, right_3, bottom_3), uint3(top_3, front_3, back_3));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_3  ? 4 :
                          max_dir == left_3   ? 0 :
                          max_dir == right_3  ? 1 :
                          max_dir == back_3   ? 5 :
                          max_dir == top_3    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_2, right_2, bottom_2), uint3(top_2, front_2, back_2));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_2  ? 4 :
                          max_dir == left_2   ? 0 :
                          max_dir == right_2  ? 1 :
                          max_dir == back_2   ? 5 :
                          max_dir == top_2    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_1, right_1, bottom_1), uint3(top_1, front_1, back_1));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_1  ? 4 :
                          max_dir == left_1   ? 0 :
                          max_dir == right_1  ? 1 :
                          max_dir == back_1   ? 5 :
                          max_dir == top_1    ? 4 : 2;

                bits_z <<= 4;

                max_vec = max(uint3(left_0, right_0, bottom_0), uint3(top_0, front_0, back_0));
                max_dir = max(max_vec.x, max(max_vec.y, max_vec.z));

                bits_z += max_dir == front_0  ? 4 :
                          max_dir == left_0   ? 0 :
                          max_dir == right_0  ? 1 :
                          max_dir == back_0   ? 5 :
                          max_dir == top_0    ? 4 : 2;
                
                return uint3(bits_x, bits_y, bits_z);
            }
            ENDHLSL
        }
    }
}
