Shader "Voxel/BitFixed"
{
    Properties
    {
        
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
            //#pragma target 3.0
            //#pragma enable_d3d11_debug_symbols

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
                uint lowbits = 0;
                uint highbits = 0;

                /*
                // X Moves
                uint lowbits = 0x550055;
                uint highbits = 0x550055;
                
                lowbits |= lowbits << 1;
                highbits |= highbits << 1;

                lowbits |= lowbits << 8;
                highbits |= highbits << 8;
                */

                /*
                // Y Moves
                uint lowbits = 0x3333;
                uint highbits = 0x3333;
                
                lowbits |= lowbits << 2;
                highbits |= highbits << 2;

                lowbits |= lowbits << 16;
                highbits |= highbits << 16;
                */

                /*
                // Z Moves
                uint lowbits = 0x550055;
                uint highbits = 0x550055;
                
                lowbits |= lowbits << 1;
                highbits |= highbits << 1;

                lowbits |= lowbits << 8;
                highbits |= highbits << 8;
                */
                //IN.localTexcoord.xyz / _CustomRenderTextureInfo.xyz
                insert(encode(uint3(IN.localTexcoord.xyz / _CustomRenderTextureInfo.xyz)), lowbits, highbits);

                return uint2(lowbits, highbits);
            }

        ENDHLSL
        }
    }
}
