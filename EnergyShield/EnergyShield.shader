Shader "taecg/URP/EnergyShield"
{
    Properties
    {
        [Header(Base)]
        _BaseMap("BaseMap", 2D) = "white" {}
        _FresnelColor("Fresnel Color",Color) = (1,1,1,1)
        [PowerSlider(3)]_FresnelPower("FresnelPower",Range(0,15)) = 5

        [Header(HighLight)]
        _HighLightColor("HighLight Color",Color) = (1,1,1,1)
        _HighLightFade("HighLight Fade",float) = 3

        [Header(Distort)]
        _Tiling("Distort Tiling",float) = 6
        _Distort("Distort Intensity",Range(0,1))=0.4
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            // Blend One One
            Name "Unlit"
            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS       : POSITION;
                float2 uv               : TEXCOORD0;
                half3 normal            : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float4 uv           : TEXCOORD0;
                float fogCoord      : TEXCOORD1;
                float3 positionVS   : TEXCOORD2;
                half3 normalWS      : TEXCOORD3;
                half3 viewWS        : TEXCOORD4;
            };
//CBUFFER直接的值用于暴露参数
            CBUFFER_START(UnityPerMaterial)
            half4 _HighLightColor;
            half _HighLightFade;
            half4 _FresnelColor;
            half _FresnelPower;
            half _Tiling;
            half _Distort;
            float4 _BaseMap_ST;
            CBUFFER_END

            
            TEXTURE2D (_BaseMap);SAMPLER(sampler_BaseMap);
            TEXTURE2D (_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);//深度图
            TEXTURE2D (_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);//屏幕抓取

            // #define smp _linear_clampU_mirrorV
            // SAMPLER(smp);

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                //将顶点从本地空间转换到世界空间
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                //将顶点从世界空间转换到观察空间
                o.positionVS = TransformWorldToView(positionWS);//用于能力罩物体的位置与其他物体的位置进行比较
                o.normalWS = TransformObjectToWorldNormal(v.normal);//世界空间下的法线
                o.viewWS = normalize(_WorldSpaceCameraPos - positionWS);
                o.positionCS = TransformWViewToHClip(o.positionVS);
                o.uv.xy = v.uv;
                o.uv.zw = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 c;

                float2 screenUV = i.positionCS.xy/_ScreenParams.xy;
                half4 depthMap = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV);
                //获取片断对应深度图中的像素在观察空间下的Z值
                half depth = LinearEyeDepth(depthMap.r,_ZBufferParams);
                half4 hightlight = depth + i.positionVS.z;//i.position.z是负值，接近的部分会呈现黑色
                hightlight *= _HighLightFade;//缩小高光范围
                hightlight = 1 - hightlight;//将高光颜色变反
                hightlight *= _HighLightColor;
                hightlight = saturate(hightlight);
                c = hightlight;

                //fresnel外发光
                //pow(max(0,dot(N,V)),Intensity)   fresnel =1-pow(max(0,dot(N,V)),intensity)实现内暗外亮效果，但是这么些intensity变打，暗区会变小
                half3 N = i.normalWS;
                half3 V = i.viewWS;//视线方向
                half NdotV = 1 - saturate(dot(N,V));
                half4 fresnel = pow(abs(NdotV),_FresnelPower);
                fresnel *= _FresnelColor;

                c += fresnel;
                // half4 c;
                // half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.zw);
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.zw + float2(0,_Time.y));
                c += baseMap * 0.1;//减弱蜂窝图亮度

                // half4 baseMap01 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.zw + float2(0,_Time.y));
                //!!!当前帧的抓屏 扭曲
                // float2 distortUV = lerp(screenUV,baseMap.rr,_Distort);
                // half4 opaqueTex = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, distortUV);//抓屏后的贴图
                // half4 distort = half4(opaqueTex.rgb,1);//将图放到扰动贴图中

                half flowMask = frac(i.uv.y * _Tiling + _Time.y);
                //distort *= pow(flowMask,0.1);//pow 0.1减少flowMask的影响
                //c += distort;
                //!!!取消了扰动部分,不然物体视线朝向天空盒边界时会出现异常
                return c*pow(flowMask,0.1);
            }
            ENDHLSL
        }
    }

    

}
