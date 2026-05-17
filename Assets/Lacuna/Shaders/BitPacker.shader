Shader "Lacuna/BitPacker"
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
           #pragma target 3.0
           //#pragma enable_d3d11_debug_symbols

           UNITY_DECLARE_TEX3D(_MainTex);
           float4   _MainTex_TexelSize;
           
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

            uint encode(uint3 xyz)
            {
                return encode(xyz.x, xyz.y, xyz.z);
            }

            uint unwrap64(uint x, uint y, uint z)
            {
                return x + y * 4 + z * 16;
                //return x + y << 2 + z << 4;
            }

            uint unwrap64(uint3 xyz)
            {
                return unwrap64(xyz.x, xyz.y, xyz.z);
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

            uint2 frag(v2f_customrendertexture IN) : SV_Target
            {
                // Prepare the data structure...
                // Each 4x4x4 texel "brick" is packed into two 32 bit integers
                // Together they are treated like a single 64 bit mask
                // High bits represent occupied voxels
                uint lowbits = 0;
                uint highbits = 0;

                // The source 3D texture is assumed to be 4x the render texture
                // The dimensions of the render texture must be a power of 2
                // Getting this wrong would be Very Bad™
                int3 texelCoordinateOffset = int3(IN.localTexcoord.xyz * _CustomRenderTextureInfo.xyz) << 2;

                // Now we step through the voxels in the source texture
                for(int x = 0; x < 4; x++)
                    for(int y = 0; y < 4; y++)
                        for(int z = 0; z < 4; z++)
                        {
                            // Compute our final texel coordinate
                            int3 texelCoordinate = int3(x, y, z) + texelCoordinateOffset;

                            //float4 texel = _MainTex.Load(uint4(texelCoordinate, 0));
                            if(_MainTex.Load(uint4(texelCoordinate, 0)).a > 0)
                                insert(encode(x, y, z), lowbits, highbits);
                        }
               
               return uint2(lowbits, highbits);
           }


           ENDHLSL
        }
    }
}
