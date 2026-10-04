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
                            uint3 loadTexcoord = uint3(x, y, z) + uint3(IN.localTexcoord.xyz * _CustomRenderTextureInfo.xyz) * 4;

                            uint left_depth = asuint(_MainTex.Load(uint4((_CustomRenderTextureInfo.z * 8 - 1) - loadTexcoord.z, (_CustomRenderTextureInfo.y * 4 - 1) + loadTexcoord.y, 0, 0)));
                            uint right_depth = asuint(_MainTex.Load(uint4((_CustomRenderTextureInfo.z * 4 - 1) + loadTexcoord.z, loadTexcoord.y, 0, 0)));
                            uint bottom_depth = asuint(_MainTex.Load(uint4(loadTexcoord.x, (_CustomRenderTextureInfo.z * 4 - 1) - loadTexcoord.z, 0, 0)));
                            uint top_depth = asuint(_MainTex.Load(uint4((_CustomRenderTextureInfo.x * 12 - 1) - loadTexcoord.x, (_CustomRenderTextureInfo.z * 8 - 1) - loadTexcoord.z, 0, 0)));
                            uint front_depth = asuint(_MainTex.Load(uint4(loadTexcoord.x, (_CustomRenderTextureInfo.y * 4 - 1) + loadTexcoord.y, 0, 0)));
                            uint back_depth = asuint(_MainTex.Load(uint4((_CustomRenderTextureInfo.x * 12 - 1) - loadTexcoord.x, loadTexcoord.y, 0, 0)));

                            if (loadTexcoord.x == (_CustomRenderTextureInfo.x * 4 - 1) - left_depth && left_depth != 0 ||
                                loadTexcoord.x == right_depth && right_depth != 0 ||
                                loadTexcoord.y == (_CustomRenderTextureInfo.y * 4 - 1) - bottom_depth && bottom_depth != 0 ||
                                loadTexcoord.y == top_depth && top_depth != 0 ||
                                loadTexcoord.z == (_CustomRenderTextureInfo.z * 4 - 1) - front_depth && front_depth != 0 ||
                                loadTexcoord.z == back_depth && back_depth != 0)
                                insert(encode(x, y, z), bits_x, bits_y);

                        }
                
                return uint2(bits_x, bits_y);
            }
            ENDHLSL
        }
    }
}
