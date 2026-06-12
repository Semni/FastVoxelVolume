Shader "Lacuna/Flyover"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Voxel Bitmask", 3D) = "white" {}
        [NoScaleOffset] _Udon_Lacuna_Color ("Lacuna Colour", 2D) = "white" {}
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

            Texture2D _Udon_Lacuna_Color;

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

                // Calculate our ray
                // This seems backwards but we need our direction first.
                float3 ray_direction = normalize(i.surface_position - i.camera_position);
                // The ray should start from the clipping plane, and bring the ray position into 0.0 to 1.0 space from -0.5 to 0.5 space.
                float3 ray_position = i.camera_position + ray_direction * _ProjectionParams.y + 0.5;

                // Do the raymarching, if we don't hit anything we can discard the pixel.
                if (!traversal(_MainTex, _MainTex_TexelSize, ray_position, ray_direction, hit_position, hit_coord, mask)) discard;

                // Write to the depth buffer. Remember to bring it back into -0.5 to 0.5 space for this.
                // For raymarching in world space.
                //float4 clip_position = mul(UNITY_MATRIX_VP, float4(hit_position - 0.5, 1));

                // For raymarching in object space.
                float4 clip_position = UnityObjectToClipPos(float4(hit_position - 0.5, 1));

                depth = clip_position.z / clip_position.w;
                
                // Best results yet, there's a weird bug I am compensating for here. I still have to work that out...
                float4 leftColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.z, hit_coord.y) + uint2(256, 256) + uint2(0, 2), 0, 0));
                float4 rightColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.zy + uint2(256, 0) + uint2(0, 2), 0, 0));
                float4 bottomColour = _Udon_Lacuna_Color.Load(uint4(uint2(hit_coord.x, 256 - hit_coord.z) + uint2(2, 0), 0, 0));
                float4 topColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, 256 - hit_coord.z) + uint2(512, 256) + uint2(-2, 0), 0, 0));
                float4 frontColour = _Udon_Lacuna_Color.Load(uint4(hit_coord.xy + uint2(0, 256) + uint2(2, 2), 0, 0));
                float4 backColour = _Udon_Lacuna_Color.Load(uint4(uint2(256 - hit_coord.x, hit_coord.y) + uint2(512, 0) + uint2(-2, 2), 0, 0));

                float3 colour = floor(leftColour.a * 256) + 2 == 256 - hit_coord.x? leftColour.rgb :
                                floor(rightColour.a * 256) - 2 == hit_coord.x ? rightColour.rgb :
                                floor(bottomColour.a * 256) + 2 == 256 - hit_coord.y ? bottomColour.rgb :
                                floor(topColour.a * 256) - 2 == hit_coord.y ? topColour.rgb :
                                floor(frontColour.a * 256) == 256 - hit_coord.z ? frontColour.rgb :
                                floor(backColour.a * 256) == hit_coord.z ? backColour.rgb :
                                float3(1, 0, 1);

                return float4(colour, 1);

            }
            ENDCG
        }
    }
}
