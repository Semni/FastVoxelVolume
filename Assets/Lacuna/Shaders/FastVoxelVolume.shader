Shader "Lacuna/FastVoxelVolume"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Voxel Bitmask", 3D) = "white" {}
        [NoScaleOffset] _Udon_3DJ_Color ("3DJ Colour", 2D) = "white" {}
        [NoScaleOffset] _Udon_Lacuna_Color ("Lacuna Colour", 2D) = "white" {}
        [Enum(3DJ Colour Mix, 0, Normal, 1, UV, 2, Mip Level, 3, Checkerboard, 4, Position, 5, 3DJ Preferred Direction, 6)] _RenderMode ("Render Mode", Integer) = 0
        _Sweep ("Sweep", Range(-16, 16)) = 0

    }
    SubShader
    {
        // I'm not sure about these tags
        // I was using Transparent, I may use AlphaTest...
        // Also, lets keep everything in object space Geometry
        Tags { "Queue"="Geometry" "DisableBatching"="True"}
        Pass
        {
            // The shader assumes a 1x1x1 cube.
            // Cull front faces so that objects intersecting the cube don't disappear.
            Cull Front

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            //#pragma enable_d3d11_debug_symbols
            #pragma target 5.0

            //#include "UnityCG.cginc"

            // We only need the vertex position so lets not import data we don't need.
            struct appdata
            {
                float4 vertex : POSITION;
            };

            // The data we need to build our ray.
            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 camera_position : TEXCOORD0;
                float3 surface_position : TEXCOORD1;
            };

            // The dimensions of the 3D texture must be a power of 2.
            // The dimensions of all sides must be the same.
            // The Color Format must be R32G32_UINT.
            UNITY_DECLARE_TEX3D(_MainTex);
            float4 _MainTex_TexelSize;

            //UNITY_DECLARE_TEX3D(_ColourTex);
            //float4 _ColourTex_TexelSize;

            Texture2D _Udon_3DJ_Color;
            SamplerState sampler_Udon_3DJ_Color;
            SamplerState _linear_clamp_sampler;
            float4 _Udon_3DJ_Color_TexelSize;

            Texture2D _Udon_Lacuna_Color;
            SamplerState sampler_Udon_Lacuna_Color;
            float4 _Udon_Lacuna_Color_TexelSize;

            uint _RenderMode;
            int _Sweep;


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                // For raymarching in world space.
                //o.camera_position = _WorldSpaceCameraPos;
                //o.surface_position = mul(unity_ObjectToWorld, v.vertex);

                // For raymarching in object space.
                o.camera_position = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1));
                o.surface_position = v.vertex;

                return o;
            }

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

            uint encode (uint3 xyz)
            {
                return encode(xyz.x, xyz.y, xyz.z);
            }

            // Our main traversal algorithm.
            bool traversal (float3 ray_position, float3 direction, out float3 hit_position, out uint3 hit_coord, out uint3 mask)
            {
                hit_position = ray_position;
                hit_coord = uint3(0, 0, 0);

                // Division is expensive, compute and store the inverse direction once.
                float3 inverse_direction = 1.0 / direction;

                {
                    // Bring the ray position into 0.0 to 1.0 space
                    //ray_position += 0.5; 

                    // Do our AABB intersection
                    float3 t1 = -ray_position * inverse_direction;
                    float3 t2 = (1.0 - ray_position) * inverse_direction;

                    float3 tmins = min(t1, t2);
                    float3 tmaxs = max(t1, t2);

                    float tmin = max(tmins.x, max(tmins.y, tmins.z));
                    float tmax = min(tmaxs.x, min(tmaxs.y, tmaxs.z));

                    // If tmin is larger than tmax we know the ray doesn't hit the bounding box and can discard it.
                    if(tmin > tmax) return false;

                    // Clamp tmin to 0.
                    tmin = max(0.0, tmin);

                    // Snap the ray to the bounding box
                    ray_position += direction * tmin;

                    // Now we scale our position into voxel space
                    ray_position *= _MainTex_TexelSize.z;

                    // Initial axis setup for an immediate hit
                    mask = tmins.x > tmins.y ? tmins.x > tmins.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : tmins.y > tmins.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
                    //stepped_axis = t.x < t.y ? t.x < t.z ? 0 : 3 : t.y < t.z ? 2 : 3;
                }

                uint3 coord;
                float3 t;
                uint3 ustep;
                float3 delta;

                {
                    // For complicated reasons I don't fully understand we'll want to use the sign of the inverse as well.
                    int3 sign_direction = sign(inverse_direction);

                    // Initalize voxel traversal.
                    coord = uint3(clamp(floor(ray_position), 0, _MainTex_TexelSize.z - 1));
                    t = (coord + 0.5 * (1 + sign_direction) - ray_position) * inverse_direction;

                    ustep = uint3(sign_direction);
                    delta = inverse_direction * sign_direction;
                }
                
                // RUN OUR MAIN TRAVERSAL LOOP HERE
                [loop]
                while (true)
                {
                    if(any(coord > uint(_MainTex_TexelSize.z) - 1u)) return false;

                    // Retrieve our bitmask
                    uint2 bitmask = asuint(_MainTex.Load(uint4(coord, 0)));

                    // If x or y are anything other than 0, there are voxels here.
                    // We need to step into the brick and traverse through it.
                    // Otherwise we can skip the entire brick.
                    if (bitmask.x || bitmask.y)
                    {
                        // Extract our hit location here.
                        // This is the dirty method that I really don't like but it works.
                        // Sort of...
                        float t_inside = dot(t, mask) - dot(delta, mask);

                        // Notice the CRIMES: We push the ray into the cube a tiny little amount to compensate for floating point imprecision.
                        // 10-05-26 HAHA FIXED!
                        //float3 hit = (ray_position + direction * t_inside + direction * 0.0001) * 4;

                        hit_position = (ray_position + direction * t_inside) * 4;

                        // We know the voxel has to be within the brick so we can clamp to the maximum and minimum brick coordinates.
                        hit_coord = uint3(clamp(floor(hit_position), coord << 2, (coord << 2) + 3));
                        float3 t0 = (hit_coord + 0.5 * (1 + sign(inverse_direction)) - hit_position) * inverse_direction;

                        [loop]
                        while(!(any((hit_coord >> 2) != coord)))
                        {
                            // Compute our bitmask offset and extract the bit.
                            uint n = encode(hit_coord & 3);
                            //uint bit = (n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)));
                            //uint bit = bitmask[n >> 5] & (1u << (n & 31));

                            // If the bit is anything other than 0 we've hit a voxel.
                            if((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32))))
                            {
                                t_inside += (dot(t0, mask) - dot(delta, mask)) * 0.25;

                                hit_position = (ray_position + direction * t_inside) * _MainTex_TexelSize.x;

                                return true;
                            }

                            mask = t0.x < t0.y ? t0.x < t0.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : t0.y < t0.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
                            hit_coord += ustep * mask;
                            t0 += delta * mask;
                        }
                    }
                    
                    mask = t.x < t.y ? t.x < t.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : t.y < t.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
                    coord += ustep * mask;
                    t += delta * mask;
                }
                // If we get to here something has gone wrong and we should discard this ray. Or not...
                return false;
            }

            float mip_map_level (in float2 texture_coordinate) // texture_coordinate = uv_MainTex * _MainTex_TexelSize.zw
            {
                float2 dx_vtc = ddx(texture_coordinate);
                float2 dy_vtc = ddy(texture_coordinate);
                float md = max(dot(dx_vtc, dx_vtc), dot(dy_vtc, dy_vtc));
                return 0.5 * log2(md);
            }

            fixed4 frag (v2f i, out float depth : SV_Depth) : SV_Target
            {
                // Prepare our variables
                float3 hit_position;
                uint3 hit_coord;
                uint3 mask;

                // Calculate our ray
                // This seems backwards but we need our direction first.
                float3 ray_direction = normalize(i.surface_position - i.camera_position);
                // The ray should start from the clipping plane, and bring the ray position into 0.0 to 1.0 space from -0.5 to 0.5 space.
                float3 ray_position = i.camera_position + ray_direction * _ProjectionParams.y + 0.5;

                // Do the raymarching, if we don't hit anything we can discard the pixel.
                if (!traversal(ray_position, ray_direction, hit_position, hit_coord, mask)) discard;

                // Write to the depth buffer. Remember to bring it back into -0.5 to 0.5 space for this.
                // For raymarching in world space.
                //float4 clip_position = mul(UNITY_MATRIX_VP, float4(hit_position - 0.5, 1));

                // For raymarching in object space.
                float4 clip_position = UnityObjectToClipPos(float4(hit_position - 0.5, 1));

                depth = clip_position.z / clip_position.w;

                // Calculate normals and uv position for use later...
                float3 normal = -(int3)mask * sign(ray_direction);
                float2 uv = mask.x == 1 ? hit_position.yz : mask.y == 1 ? hit_position.xz : hit_position.xy;

                uint2 bitmask = asuint(_MainTex.Load(uint4(hit_coord >> 2, 0)).zw);
                int n = encode((hit_coord & 3) >> 1) * 8;
                

                switch (_RenderMode)
                {
                    case 0: // Colour

                        float4 leftColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0));
                        float4 rightColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0));
                        float4 bottomColour = _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0));
                        float4 topColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0));
                        float4 frontColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0));
                        float4 backColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0));

                        float3 colour = floor(leftColour.a * 256 + _Sweep) == (256 - hit_coord.x) ? leftColour.rgb :
                                        //floor(rightColour.a * 256) == hit_coord.x ? rightColour.rgb :
                                        //floor(bottomColour.a * 256) == 256 - hit_coord.y ? bottomColour.rgb :
                                        //floor(topColour.a * 256) == hit_coord.y ? topColour.rgb :
                                        //floor(frontColour.a * 256) == 256 - hit_coord.z ? frontColour.rgb :
                                        //floor(backColour.a * 256) == hit_coord.z ? backColour.rgb :
                                        float3(0, 1, 0);

                        return float4(colour, 1);

                        uint dirbitmask = (n < 32) ? ((bitmask.x >> n) & 0xff) : ((bitmask.y >> (n - 32) & 0xff));
                        switch ((n < 32) ? ((bitmask.x >> n) & 0xff) : ((bitmask.y >> (n - 32) & 0xff)))
                        {
                            case 1: // Left only
                                return _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0));
                            break;
                            case 2: // Right only
                                return _Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0));
                            break;
                            case 4: // Bottom only
                                return _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0));
                            break;
                            case 8: // Top only
                                return _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0));
                            break;
                            case 16: // Front only
                                return _Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0));
                            break;
                            case 32: // Back only
                                return _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0));
                            break;
                            case 9: // Left and Top
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0)), 0.5);
                            break;
                            case 10: // Right and Top
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0)), 0.5);
                            break;
                            case 24: // Front and Top
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0)), 0.5);
                            break;
                            case 40: // Back and Top
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + float2(512, 256), 0, 0)), 0.5);
                            break;
                            case 5: // Left and Bottom
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0)), 0.5);
                            break;
                            case 6: // Right and Bottom
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0)), 0.5);
                            break;
                            case 20: // Front and Bottom
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0)), 0.5);
                            break;
                            case 36: // Back and Bottom
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z), 0, 0)), 0.5);
                            break;
                            case 17: // Left and Front
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0)), 0.5);
                            break;
                            case 33: // Left and Back
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0)), 0.5);
                            break;
                            case 18: // Right and Front
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0)), 0.5);
                            break;
                            case 34: // Right and Back
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0)), 0.5);
                            break;
                            case 3: // Left and Right
                                return lerp(_Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0), 0, 0)), 0.5);
                            break;
                            case 48: // Front and Back
                                return lerp(_Udon_Lacuna_Color.Load(uint4(hit_coord.xy + float2(0, 256), 0, 0)), _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + float2(512, 0), 0, 0)), 0.5);
                            break;
                            default:
                            break;
                        }
                        //return _ColourTex.Load(uint4(hit_coord, 1));
                    break;
                    case 1: //Normal
                        //return dot(normal, -ray_direction);
                        return float4(max(normal.xyz, 0) - min(normal.yxz + normal.zyx, 0), 1);
                    break;
                    case 2: // UV
                        return float4(uv, 0, 1);
                    break;
                    case 3: // Mip stuff
                        float miplevel = mip_map_level(hit_position * _MainTex_TexelSize.zw * 4);
                        return float4(1 - saturate(miplevel), 1 - saturate(-miplevel), 0, 1);
                    break;
                    case 4: // Checkerboard pattern.
                        return ((hit_coord.x ^ hit_coord.y ^ hit_coord.z) & 1);
                    break;
                    case 5: // Position
                        return float4(hit_position, 1);
                    break;
                    case 6: // 3DJ
                        //uint2 bitmask = asuint(_MainTex.Load(uint4(hit_coord >> 2, 0)).zw);
                        //int n = encode((hit_coord & 3) >> 1) * 8;

                        //hit_position += float3(0.5 * 0.25, 0.5 * 0.25, 0.5 * 0.25) * _MainTex_TexelSize.x;

                        //(hit_coord * _MainTex_TexelSize.z)
                        hit_position = hit_coord * _MainTex_TexelSize.x * 0.25;

                        switch (int(normal.x + normal.y * 2 + normal.z * 3))
                        {
                            case -1: // -X Left
                                return ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            case 1: // +X Right
                                return (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            case -2: // -Y Bottom
                                return (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            case 2: // +Y Top
                                return (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            case -3: // -Z Front
                                return (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            case 3: // +Z Back
                                return (((n + 5) < 32) ? (bitmask.x & (1u << (n + 5))) : (bitmask.y & (1u << ((n + 5) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 1) < 32) ? (bitmask.x & (1u << (n + 1))) : (bitmask.y & (1u << ((n + 1) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.zy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 0) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    ((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.z, hit_position.y) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 3) < 32) ? (bitmask.x & (1u << (n + 3))) : (bitmask.y & (1u << ((n + 3) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(1. - hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(640, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 2) < 32) ? (bitmask.x & (1u << (n + 2))) : (bitmask.y & (1u << ((n + 2) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, float2(hit_position.x, 1. - hit_position.z) * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    (((n + 4) < 32) ? (bitmask.x & (1u << (n + 4))) : (bitmask.y & (1u << ((n + 4) - 32)))) ? _Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, hit_position.xy * float2(320, 530) * _Udon_3DJ_Color_TexelSize.xy + float2(0, 530) * _Udon_3DJ_Color_TexelSize.xy) : 
                                    float4(1, 0, 1, 1);
                            break;
                            default:
                            break;
                        }
                    break;
                }

                // If this happens something has gone wrong.
                return float4(1, 0, 1, 1);
            }
            ENDCG
        }
    }
}
