Shader "Lacuna/Octave_Packer"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Texture", 3D) = "white" {}
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

            Texture3D _MainTex;

            uint2 frag (v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into two 32 bit integers
                // Together they are treated like a single 64 bit mask
                // High bits represent occupied voxels
                uint bits_x = 0;
                uint bits_y = 0;

                // The source 3D texture is assumed to be 4x the render texture
                // The source textures are also assumed to be all the same size
                // The dimensions of the render texture must be a power of 2
                // Getting this wrong would be Very Bad™
                
                int3 texelCoordinateOffset = int3(IN.localTexcoord.xyz * _CustomRenderTextureInfo.xyz) << 2;


                // Now we step through our voxels
                [unroll]
                for (uint x = 0; x < 4; x++)
                    for (uint y = 0; y < 4; y++)
                        for (uint z = 0; z < 4; z++)
                        {
                            // Compute our final texel coordinate
                            int3 texelCoordinate = int3(x, y, z) + texelCoordinateOffset;

                            // Retrieve our bitmask
                            uint2 bitmask = asuint(_MainTex.Load(uint4(texelCoordinate, 0)));

                            if(bitmask.x || bitmask.y)
                                insert(encode(x, y, z), bits_x, bits_y);
                        }
                
                return uint2(bits_x, bits_y);
            }
            ENDHLSL
        }
    }
}
