Shader "Lacuna/Flyover_Lacuna_Bitmask"
{
    Properties
    {
        [NoScaleOffset] _Udon_Lacuna_Depth ("Lacuna Depth", 2D) = "white" {}
        _SobelOffset("Sobel Filter Width", Range(0.5, 2.0)) = 1.0
        _SobelSensitivity("Sobel Filter Sensitivity", Range(0.01, 0.2)) = 0.1
        _VoxelSensitivity ("Voxel Sensitivity", Range(0.25, 4)) = 1.0
        _SampleThreshold ("Sampling Threshold", Range(0, 256)) = 0
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

            Texture2D _Udon_Lacuna_Depth;
            SamplerState sampler_Udon_Lacuna_Depth;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_Lacuna_Depth_TexelSize;

            float _SobelOffset;
            float _SobelSensitivity;
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
                low |= n < 32 ? 1u << n : 0u;
                high |= n >= 32 && n < 64 ? 1u << (n - 32) : 0u;
                /*if(n < 32)
                {
                    low = low | 1u << n;
                }
                else if(n < 64)
                {
                    high = high | 1u << (n - 32);
                }*/
            }

            float SobelDepth(float ldc, float ldl, float ldr, float ldu, float ldd)
            {
                return abs(ldl - ldc) +
                    abs(ldr - ldc) +
                    abs(ldu - ldc) +
                    abs(ldd - ldc);
            }

            float SobelSampleDepth(Texture2D t, uint2 uv, uint3 offset)
            {
                float pixelCenter = t.Load(uint4(uv, 0, 0)).a;
                float pixelLeft = t.Load(uint4(uv - offset.xz, 0, 0)).a;
                float pixelRight = t.Load(uint4(uv + offset.xz, 0, 0)).a;
                float pixelUp = t.Load(uint4(uv + offset.zy, 0, 0)).a;
                float pixelDown = t.Load(uint4(uv - offset.zy, 0, 0)).a;

                return SobelDepth(pixelCenter, pixelLeft, pixelRight, pixelUp, pixelDown);
            }

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

                uint3 offset = uint3(_SobelOffset, _SobelOffset, 0);

                // Now we step through our voxels
                [unroll]
                for (uint x = 0; x < 4; x++)
                    for (uint y = 0; y < 4; y++)
                        for (uint z = 0; z < 4; z++)
                        {
                            uint3 loadTexcoord = uint3(x, y, z) + IN.localTexcoord.xyz * 256;

                            uint2 leftLoadTexcoord = uint2(256 - loadTexcoord.z, loadTexcoord.y) + float2(256, 256);
                            uint2 rightLoadTexcoord = loadTexcoord.zy + float2(256, 0);
                            uint2 bottomLoadTexcoord = uint2(loadTexcoord.x, 256 - loadTexcoord.z);
                            uint2 topLoadTexcoord = uint2(256 - loadTexcoord.x, 256 - loadTexcoord.z) + float2(512, 256);
                            uint2 frontLoadTexcoord = loadTexcoord.xy + float2(0, 256);
                            uint2 backLoadTexcoord = uint2(256 - loadTexcoord.x, loadTexcoord.y) + float2(512, 0);

                            uint left_depth_texel = _Udon_Lacuna_Depth.Load(uint4(leftLoadTexcoord, 0, 0)).a * 256; // -X Left
                            uint right_depth_texel = _Udon_Lacuna_Depth.Load(uint4(rightLoadTexcoord, 0, 0)).a * 256; // +X Right
                            uint bottom_depth_texel = _Udon_Lacuna_Depth.Load(uint4(bottomLoadTexcoord, 0, 0)).a * 256; // -Y Bottom
                            uint top_depth_texel = _Udon_Lacuna_Depth.Load(uint4(topLoadTexcoord, 0, 0)).a * 256; // +Y Top
                            uint front_depth_texel = _Udon_Lacuna_Depth.Load(uint4(frontLoadTexcoord, 0, 0)).a * 256; // -Z Front
                            uint back_depth_texel = _Udon_Lacuna_Depth.Load(uint4(backLoadTexcoord, 0, 0)).a * 256; // +Z Back

                            float left_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, leftLoadTexcoord, offset); // -X Left
                            float right_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, rightLoadTexcoord, offset); // +X Right
                            float bottom_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, bottomLoadTexcoord, offset); // -Y Bottom
                            float top_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, topLoadTexcoord, offset); // +Y Top
                            float front_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, frontLoadTexcoord, offset); // -Z Front
                            float back_depth_texel_sobel = SobelSampleDepth(_Udon_Lacuna_Depth, backLoadTexcoord, offset); // +Z Back

                            bool left_depth_texel_flag = left_depth_texel_sobel < _SobelSensitivity && left_depth_texel > _SampleThreshold && (256 - loadTexcoord.x) == left_depth_texel;
                            bool right_depth_texel_flag = right_depth_texel_sobel < _SobelSensitivity && right_depth_texel > _SampleThreshold && loadTexcoord.x == right_depth_texel;
                            bool bottom_depth_texel_flag = bottom_depth_texel_sobel < _SobelSensitivity && bottom_depth_texel > _SampleThreshold && (256 - loadTexcoord.y) == bottom_depth_texel;
                            bool top_depth_texel_flag = top_depth_texel_sobel < _SobelSensitivity && top_depth_texel > _SampleThreshold && loadTexcoord.y == top_depth_texel;
                            bool front_depth_texel_flag = front_depth_texel_sobel < _SobelSensitivity && front_depth_texel > _SampleThreshold && (256 - loadTexcoord.z) == front_depth_texel;
                            bool back_depth_texel_flag = back_depth_texel_sobel < _SobelSensitivity && back_depth_texel > _SampleThreshold && loadTexcoord.z == back_depth_texel;

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
