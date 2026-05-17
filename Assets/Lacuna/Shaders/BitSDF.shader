Shader "Lacuna/BitSDF"
{
    Properties
    {
        [Enum(Sphere, 0, Torus, 1, Capped Cone, 2, Cut Hollow Sphere, 3, Dynamic, 4, Filled, 5)] _RenderMode ("Render Mode", Integer) = 0
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

            uint _RenderMode;
           
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

            float sdSphere(float3 p, float r)
            {
                return length(p) - r;
            }

            float sdTorus(float3 p, float2 t)
            {
                float2 q = float2(length(p.xz) - t.x, p.y);
                return length(q) - t.y;
            }

            float sdCappedTorus(float3 p, float2 sc, float ra, float rb)
            {
                p.x = abs(p.x);
                float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
                return sqrt(dot(p, p) + ra * ra - 2.0 * ra * k) - rb;
            }

            float sdCappedCone(float3 p, float h, float r1, float  r2)
            {
                float2 q = float2(length(p.xz), p.y);
                float2 k1 = float2(r2, h);
                float2 k2 = float2(r2 - r1, 2.0 * h);
                float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
                float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
                float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
                return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
            }

            float sdCutHollowSphere(float3 p, float r, float h, float t)
            {
                float w = sqrt(r * r - h * h);
                float2 q = float2(length(p.xz), p.y);
                return ((h * q.x < w * q.y) ? length(q - float2(w, h)) : abs(length(q) - r)) - t;
            }

            float opSmoothUinion(float a, float b, float k)
            {
                k *= 4.0;
                float h = max(k - abs(a - b), 0.0);
                return min(a, b) - h * h * 0.25 / k;
            }

            float map(float3 p)
            {
                float result = 1;
                switch(_RenderMode)
                {
                    case 0: // Sphere
                        result = min(result, sdSphere(p, 0.35));
                    break;
                    case 1: // Torus
                        result = min(result, sdTorus(p, float2(0.35, 0.1)));
                    break;
                    case 2: // Capped Cone
                        result = min(result, sdCappedCone(p, 0.35, 0.5, 0.2));
                    break;
                    case 3: // Cut Hollow Sphere
                        result = min(result, sdCutHollowSphere(p, 0.35, 0.1, 0.05));
                    break;
                    case 4: // Dynamic
                        //result = min(result, sdTorus(p, float2(0.35, 0.1)));
                        result = min(result, sdSphere(p + float3(0, _SinTime.w, 0) * 0.35, 0.1));

                        result = min(result, opSmoothUinion(sdTorus(p, float2(0.35, 0.1)), sdSphere(p + float3(_SinTime.w, _CosTime.w, 0) * 0.35, 0.1), 0.05));
                    break;
                    case 5: // Filled Cube
                        result = 0;
                    break;
                }
                return result;
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
                //int3 texelCoordinateOffset = int3(IN.localTexcoord.xyz * _CustomRenderTextureInfo.xyz) << 2;

                float3 inverse_texelsize = 1. / _CustomRenderTextureInfo.xyz;

                // Now we step through the voxels in the source texture
                for(int x = 0; x < 4; x++)
                    for(int y = 0; y < 4; y++)
                        for(int z = 0; z < 4; z++)
                        {
                            // Compute our final texel coordinate
                            //int3 texelCoordinate = int3(x, y, z) + texelCoordinateOffset;
                            float3 p = IN.localTexcoord.xyz + float3(x, y, z) * inverse_texelsize * 0.25;
                            if(map(p + float3(-0.5, -0.5, -0.5)) <= 0)
                                insert(encode(x, y, z), lowbits, highbits);

                            //float4 texel = _MainTex.Load(uint4(texelCoordinate, 0));
                            //if(_MainTex.Load(uint4(texelCoordinate, 0)).a > 0)
                            //    insert(encode(x, y, z), lowbits, highbits);
                        }
               
               return uint2(lowbits, highbits);
           }


           ENDHLSL
        }
    }
}
