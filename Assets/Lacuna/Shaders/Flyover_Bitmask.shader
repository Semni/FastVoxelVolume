Shader "Lacuna/Flyover_Bitmask"
{
    Properties
    {
        [NoScaleOffset] _Udon_Lacuna_Depth ("Lacuna Depth", 2D) = "white" {}
        _SobelOffset ("Sobel Filter Width", Range(0.5, 2.0)) = 1.0
        _SobelSensitivity ("Sobel Filter Sensitivity", Range(0.01, 0.2)) = 0.1
        _SampleThreshold ("Sampling Threshold", Range(0, 1)) = 0.02
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

            Texture2D _Udon_Lacuna_Depth;
            SamplerState sampler_Udon_Lacuna_Depth;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_Lacuna_Depth_TexelSize;
            
            float _SobelOffset;
            float _SobelSensitivity;
            float _SampleThreshold;

            uint2 frag (v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into two 32 bit integers
                // Together they are treated like a single 64 bit mask
                // High bits represent occupied voxels
                uint bits_x = 0;
                uint bits_y = 0;

                // The 3D render texture must be a quarter of the size of the source texture
                // It also must be a cube
                // Getting this wrong would be Very Bad™

                // Now we step through our voxels
                [unroll]
                for (uint x = 0; x < 4; x++)
                    for (uint y = 0; y < 4; y++)
                        for (uint z = 0; z < 4; z++)
                        {
                            uint3 loadTexcoord = uint3(x, y, z) + IN.localTexcoord.xyz * _CustomRenderTextureInfo.xyz * 4;

                            uint2 leftLoadTexcoord = uint2(_CustomRenderTextureInfo.z * 4 - loadTexcoord.z, loadTexcoord.y) + _CustomRenderTextureInfo.zy * 4;
                            uint2 rightLoadTexcoord = loadTexcoord.zy + uint2(_CustomRenderTextureInfo.z * 4, 0);
                            uint2 bottomLoadTexcoord = uint2(loadTexcoord.x, _CustomRenderTextureInfo.z * 4 - loadTexcoord.z);
                            uint2 topLoadTexcoord = uint2(_CustomRenderTextureInfo.x * 4 - loadTexcoord.x, _CustomRenderTextureInfo.z * 4 - loadTexcoord.z) + _CustomRenderTextureInfo.xz * uint2(8, 4);
                            uint2 frontLoadTexcoord = loadTexcoord.xy + uint2(0, _CustomRenderTextureInfo.y * 4);
                            uint2 backLoadTexcoord = uint2(_CustomRenderTextureInfo.x * 4 - loadTexcoord.x, loadTexcoord.y) + uint2(_CustomRenderTextureInfo.y * 8, 0);

                            uint left_depth_texel = _Udon_Lacuna_Depth.Load(uint4(leftLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.x * 4; // -X Left
                            uint right_depth_texel = _Udon_Lacuna_Depth.Load(uint4(rightLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.x * 4; // +X Right
                            uint bottom_depth_texel = _Udon_Lacuna_Depth.Load(uint4(bottomLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.y * 4; // -Y Bottom
                            uint top_depth_texel = _Udon_Lacuna_Depth.Load(uint4(topLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.y * 4; // +Y Top
                            uint front_depth_texel = _Udon_Lacuna_Depth.Load(uint4(frontLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.z * 4; // -Z Front
                            uint back_depth_texel = _Udon_Lacuna_Depth.Load(uint4(backLoadTexcoord, 0, 0)).a * _CustomRenderTextureInfo.z * 4; // +Z Back

                            float left_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, leftLoadTexcoord, _SobelOffset); // -X Left
                            float right_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, rightLoadTexcoord, _SobelOffset); // +X Right
                            float bottom_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, bottomLoadTexcoord, _SobelOffset); // -Y Bottom
                            float top_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, topLoadTexcoord, _SobelOffset); // +Y Top
                            float front_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, frontLoadTexcoord, _SobelOffset); // -Z Front
                            float back_depth_texel_sobel = SobelLoadDepth(_Udon_Lacuna_Depth, backLoadTexcoord, _SobelOffset); // +Z Back

                            bool left_depth_texel_flag =    left_depth_texel_sobel < _SobelSensitivity && 
                                                            left_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.x * 4) && 
                                                            (uint)(_CustomRenderTextureInfo.x * 4 - loadTexcoord.x) == left_depth_texel;
                            bool right_depth_texel_flag =   right_depth_texel_sobel < _SobelSensitivity && 
                                                            right_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.x * 4) && 
                                                            loadTexcoord.x == right_depth_texel;
                            bool bottom_depth_texel_flag =  bottom_depth_texel_sobel < _SobelSensitivity && 
                                                            bottom_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.y * 4) && 
                                                            (uint)(_CustomRenderTextureInfo.y * 4 - loadTexcoord.y) == bottom_depth_texel;
                            bool top_depth_texel_flag =     top_depth_texel_sobel < _SobelSensitivity && 
                                                            top_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.y * 4) && 
                                                            loadTexcoord.y == top_depth_texel;
                            bool front_depth_texel_flag =   front_depth_texel_sobel < _SobelSensitivity && 
                                                            front_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.z * 4) && 
                                                            (uint)(_CustomRenderTextureInfo.z * 4 - loadTexcoord.z) == front_depth_texel;
                            bool back_depth_texel_flag =    back_depth_texel_sobel < _SobelSensitivity && 
                                                            back_depth_texel > (uint)(_SampleThreshold * _CustomRenderTextureInfo.z * 4) && 
                                                            loadTexcoord.z == back_depth_texel;

                            if(left_depth_texel_flag || right_depth_texel_flag || bottom_depth_texel_flag || top_depth_texel_flag || front_depth_texel_flag || back_depth_texel_flag)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }
                
                return uint2(bits_x, bits_y);
            }
            ENDHLSL
        }
    }
}
