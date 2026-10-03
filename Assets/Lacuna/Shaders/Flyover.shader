Shader "Lacuna/Flyover"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Voxel Bitmask", 3D) = "white" {}
        //[NoScaleOffset] _OctaveTex_1 ("Octave 1", 3D) = "white" {}
        //[NoScaleOffset] _OctaveTex_2 ("Octave 2", 3D) = "white" {}
        [NoScaleOffset] _Udon_Lacuna_Color ("Lacuna Colour", 2D) = "white" {}
        [NoScaleOffset] _DepthTex ("Flyover Depthmap", 2D) = "white" {}
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

            #include "LacunaCG.cginc"

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

            //UNITY_DECLARE_TEX3D(_OctaveTex_1);
            //float4 _OctaveTex_1_TexelSize;

            //UNITY_DECLARE_TEX3D(_OctaveTex_2);
            //float4 _OctaveTex_2_TexelSize;

            Texture2D _Udon_Lacuna_Color;

            Texture2D _DepthTex;

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            float4 _Udon_3DJ_Depth_TexelSize;

            SamplerState _linear_clamp_sampler;

            float _VRChatMirrorMode;
            float3 _VRChatMirrorCameraPos;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                // For raymarching in world space.
                //o.camera_position = _WorldSpaceCameraPos;
                //o.surface_position = mul(unity_ObjectToWorld, v.vertex);

                // For raymarching in object space.
                o.camera_position = _VRChatMirrorMode == 0 ? mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)) :
                                                             mul(unity_WorldToObject, float4(_VRChatMirrorCameraPos, 1));
                o.surface_position = v.vertex;

                return o;
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
                //float4 nearPlane = mul(float4(0, 0, -1, 1), UNITY_MATRIX_VP);
                //nearPlane = nearPlane / length(nearPlane.xyz);

                // Calculate our ray
                // This seems backwards but we need our direction first.
                float3 ray_direction = normalize(i.surface_position - i.camera_position);
                // The ray should start from the clipping plane, and bring the ray position into 0.0 to 1.0 space from -0.5 to 0.5 space.
                float3 ray_position = i.camera_position + ray_direction * _ProjectionParams.y + 0.5;
                //float3 ray_position = i.camera_position + ray_direction * planeIntersect(i.camera_position, ray_direction, nearPlane) + 0.5;

                // Do the raymarching, if we don't hit anything we can discard the pixel.
                //if (!traversal(_OctaveTex_2, _OctaveTex_2_TexelSize, ray_position, ray_direction, hit_position, hit_coord, mask)) discard;
                //if (!traversal(_OctaveTex_1, _OctaveTex_1_TexelSize, hit_position, ray_direction, hit_position, hit_coord, mask)) discard;
                if (!traversal(_MainTex, _MainTex_TexelSize, ray_position, ray_direction, hit_position, hit_coord, mask)) discard;

                // Write to the depth buffer. Remember to bring it back into -0.5 to 0.5 space for this.
                // For raymarching in world space.
                //float4 clip_position = mul(UNITY_MATRIX_VP, float4(hit_position - 0.5, 1));

                // For raymarching in object space.
                float4 clip_position = UnityObjectToClipPos(float4(hit_position - 0.5, 1));

                depth = clip_position.z / clip_position.w;

                bool left_depth_texel_flag = hit_coord.x == 255 - asuint(_DepthTex.Load(uint4(511 - hit_coord.z, 255 + hit_coord.y, 0, 0)));
                bool right_depth_texel_flag = hit_coord.x == asuint(_DepthTex.Load(uint4(255 + hit_coord.z, hit_coord.y, 0, 0)));
                bool bottom_depth_texel_flag = hit_coord.y == 255 - asuint(_DepthTex.Load(uint4(hit_coord.x, 255 - hit_coord.z, 0, 0)));
                bool top_depth_texel_flag = hit_coord.y == asuint(_DepthTex.Load(uint4(767 - hit_coord.x, 511 - hit_coord.z, 0, 0)));
                bool front_depth_texel_flag = hit_coord.z == 255 - asuint(_DepthTex.Load(uint4(hit_coord.x, 255 + hit_coord.y, 0, 0)));
                bool back_depth_texel_flag = hit_coord.z == asuint(_DepthTex.Load(uint4(767 - hit_coord.x, hit_coord.y, 0, 0)));
                
                // Best results yet, there's a weird bug I am compensating for here. I still have to work that out...
                // 03-10-2026 HAHAHA FIXED!
                float4 leftColour = _Udon_Lacuna_Color.Load(uint4(511 - hit_coord.z, 255 + hit_coord.y, 0, 0));
                float4 rightColour = _Udon_Lacuna_Color.Load(uint4(255 + hit_coord.z, hit_coord.y, 0, 0));
                float4 bottomColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.x, 255 - hit_coord.z, 0, 0));
                float4 topColour = _Udon_Lacuna_Color.Load(uint4(767 - hit_coord.x, 511 - hit_coord.z, 0, 0));
                float4 frontColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.x, 255 + hit_coord.y, 0, 0));
                float4 backColour = _Udon_Lacuna_Color.Load(uint4(767 - hit_coord.x, hit_coord.y, 0, 0));

                float3 colour = left_depth_texel_flag ? leftColour.rgb :
                                right_depth_texel_flag ? rightColour.rgb :
                                bottom_depth_texel_flag ? bottomColour.rgb :
                                top_depth_texel_flag ? topColour.rgb :
                                front_depth_texel_flag ? frontColour.rgb :
                                back_depth_texel_flag ? backColour.rgb :
                                float3(1, 0, 1);
                //colour = left_depth_texel_flag ? float3(1, 0, 0) : float3(1, 0, 1);   

                return float4(colour, 1);

            }
            ENDCG
        }
    }
}
