Shader "Lacuna/3DJ_To_Lacuna"
{
    Properties
    {
        [NoScaleOffset] _Udon_3DJ_Color ("3DJ Colour", 2D) = "white" {}
        [NoScaleOffset] _Udon_3DJ_Depth ("3DJ Depth", 2D) = "white" {}
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

            Texture2D _Udon_3DJ_Color;
            SamplerState sampler_Udon_3DJ_Color;
            float4 _Udon_3DJ_Color_TexelSize;

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            float4 _Udon_3DJ_Depth_TexelSize;

            SamplerState _linear_clamp_sampler;

            float4 frag (v2f_customrendertexture IN) : SV_Target
            {
                return float4(_Udon_3DJ_Color.Sample(_linear_clamp_sampler, IN.localTexcoord.xy).rgb, _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, IN.localTexcoord.xy).r);
            }
            ENDHLSL
        }
    }
}
