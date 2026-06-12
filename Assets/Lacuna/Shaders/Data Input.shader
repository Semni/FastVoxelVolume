Shader "Lacuna/Player Data Input"
{
    Properties
    {
        //_Position("Position", Vector) = (0,0,0,0)
		_Rotation("Rotation", Float) = 0
		_Scale("Scale", Float) = 0
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

            uniform float _Rotation;
            uniform float _Scale;

            float4 frag (v2f_customrendertexture IN) : SV_Target
            {
                return float4((int(floor(_Rotation * 100.0)) >> int(floor(IN.localTexcoord.xy.x * 20.0))) & 1, (int(floor(_Scale * 100.0)) >> int(floor(IN.localTexcoord.xy.x * 20.0))) & 1, 0, 0);
            }
            ENDHLSL
        }
    }
}
