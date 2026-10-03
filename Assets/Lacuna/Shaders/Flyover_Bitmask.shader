Shader "Lacuna/Flyover_Bitmask"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Flyover Depthmap", 2D) = "white" {}
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

            Texture2D _MainTex;

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
                            uint3 loadTexcoord = uint3(x, y, z) + uint3(IN.localTexcoord.xyz * 64) * 4;

                            bool left_depth_texel_flag = loadTexcoord.x == 255 - asuint(_MainTex.Load(uint4(511 - loadTexcoord.z, 255 + loadTexcoord.y, 0, 0)));
                            bool right_depth_texel_flag = loadTexcoord.x == asuint(_MainTex.Load(uint4(255 + loadTexcoord.z, loadTexcoord.y, 0, 0)));
                            bool bottom_depth_texel_flag = loadTexcoord.y == 255 - asuint(_MainTex.Load(uint4(loadTexcoord.x, 255 - loadTexcoord.z, 0, 0)));
                            bool top_depth_texel_flag = loadTexcoord.y == asuint(_MainTex.Load(uint4(767 - loadTexcoord.x, 511 - loadTexcoord.z, 0, 0)));
                            bool front_depth_texel_flag = loadTexcoord.z == 255 - asuint(_MainTex.Load(uint4(loadTexcoord.x, 255 + loadTexcoord.y, 0, 0)));
                            bool back_depth_texel_flag = loadTexcoord.z == asuint(_MainTex.Load(uint4(767 - loadTexcoord.x, loadTexcoord.y, 0, 0)));
                            
                            if(left_depth_texel_flag || right_depth_texel_flag || bottom_depth_texel_flag || top_depth_texel_flag || front_depth_texel_flag || back_depth_texel_flag)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }
                
                return uint2(bits_x, bits_y);
            }
            ENDHLSL
        }
    }
}
