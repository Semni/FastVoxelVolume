Shader "Lacuna/Flyover_Depthmap"
{
    Properties
    {
        _SobelOffset ("Sobel Filter Width", Range(0.5, 5.0)) = 1.0
        _SobelSensitivity ("Sobel Filter Sensitivity", Range(0.01, 0.2)) = 0.1
        _SampleThreshold ("Sampling Threshold", Range(0, 1)) = 0.02
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

            Texture2D _Udon_3DJ_Color;
            SamplerState sampler_Udon_3DJ_Color;
            float4 _Udon_3DJ_Color_TexelSize;

            Texture2D _Udon_3DJ_Depth;
            SamplerState sampler_Udon_3DJ_Depth;
            float4 _Udon_3DJ_Depth_TexelSize;

            SamplerState _linear_clamp_sampler;

            float _SobelOffset;
            float _SobelSensitivity;
            float _SampleThreshold;

            uint4 frag (v2f_customrendertexture IN) : SV_Target
            {
                float depth = _Udon_3DJ_Depth.Sample(_linear_clamp_sampler, IN.localTexcoord.xy).r;

                return uint4(uint3(_Udon_3DJ_Color.Sample(sampler_Udon_3DJ_Color, IN.localTexcoord.xy).rgb * 255) , SobelSampleDepth(_Udon_3DJ_Depth, _linear_clamp_sampler, IN.localTexcoord.xy, float3(_Udon_3DJ_Depth_TexelSize.xy, 0) * _SobelOffset) < _SobelSensitivity && depth >= _SampleThreshold ? uint(depth * 511) : 0);
            }
            ENDHLSL
        }
    }
}
