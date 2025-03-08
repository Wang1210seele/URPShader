Shader "Unlit/Water"
{
    
    Properties
    {
        _WaterColor01("Water base Color",Color)=(1,1,1,1)
        _WaterColor02("Water edge Color",Color)=(1,1,1,1)
        _Speed("Speed",Range(0,2))=1
        _WaveFloatHigh("Wave float high",Range(0,1))=1
        
        [Header(Distort)]
        _DistortDensity("Distort Density",Range(0,1))=0.5
        _DistortMap("Distort Map",2D)="white"{}
        
        [Header(Specular)]
        _SpecularColor("Specular Color",Color)=(1,1,1,1)
        _Specular("Specular Density",Float)=5
        _Smoothness("Smoothness",Float)=8
        _NormalMap("Normal Texture",2D)="white"{}
        
        [Header(Reflection)]
        _ReflectionTex("Reflection",Cube)="white"{}//use cubemap as reflection texture
        _ReflectionDensity("Reflection Density",Range(0.2,1))=0.8
        
        [Header(Foam)]
        _FoamTex("Foam Tex", 2D) = "white" {}
        _FoamRange("Foam Range",Range(0,5))=1
        _FoamColor("Foam Color",Color)=(1,1,1,1)
        _FoamNoise("Foam Noise Density",Range(0,1.0))=0.5
        
        [Header(Caustic)]
        _Caustic("Caustic",2D)="white"{}
        //_CausticRange("Caustic Range",Range(0.1,1.6))=1.5
        _CausticDensity("CausticDensity",Range(0,1))=1
    }
    SubShader
    {
        Tags {  "Queue"="Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "RenderPipeline" = "UniversalPipeline"}
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS       : POSITION;
                float2 uv               : TEXCOORD0;
                half3 normalOS            : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float4 uv           : TEXCOORD0;//xy-foam;zw - distort
                float3 positionVS   : TEXCOORD2;
                float3 positionWS   :TEXCOORD3;
                float3 normalWS     :TEXCOORD4;
                float4 normalUV    :TEXCOORD5;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _WaterColor01, _WaterColor02;
                half _Speed,_WaveFloatHigh;
            
                half _FoamRange;
                float4 _FoamTex_ST;
                half4 _FoamColor;
                half _FoamNoise;

                half _DistortDensity;
                half4 _DistortMap_ST;

                half4 _SpecularColor;
                half   _Specular;
                half _Smoothness;
                half4 _NormalMap_ST;

                half _ReflectionDensity;

                half4 _Caustic_ST;
                //half _CausticRange;
                half _CausticDensity;
            CBUFFER_END

            TEXTURE2D (_FoamTex);SAMPLER(sampler_FoamTex);
            TEXTURE2D (_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);//深度图
            TEXTURE2D (_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);//屏幕抓取
            TEXTURE2D(_DistortMap);SAMPLER(sampler_DistortMap);
            TEXTURE2D(_NormalMap);SAMPLER(sampler_NormalMap);
            TEXTURECUBE(_ReflectionTex);SAMPLER(sampler_ReflectionTex);
            TEXTURE2D(_Caustic);SAMPLER(sampler_Caustic);
            
            Varyings vert (Attributes v)
            {
                Varyings o;
                v.positionOS.y+=sin(_Time.y)*_WaveFloatHigh;
                
                o.positionWS=TransformObjectToWorld(v.positionOS);
                o.positionVS=TransformWorldToView(o.positionWS);//物体观察空间下的坐标

                half OffsetSpeed=_Time.x*_Speed;
                o.positionCS=TransformObjectToHClip(v.positionOS.xyz);
                o.uv.xy=o.positionWS.xz*_FoamTex_ST.xy+OffsetSpeed;//以世界坐标采样，防止缩放时的影响 foam
                o.uv.zw=TRANSFORM_TEX(v.uv,_DistortMap)+OffsetSpeed;
                o.normalWS=TransformObjectToWorldNormal(v.normalOS);//get normal
                o.normalUV.xy=TRANSFORM_TEX(v.uv,_NormalMap)+ OffsetSpeed;
                o.normalUV.zw=TRANSFORM_TEX(v.uv,_NormalMap)+ OffsetSpeed*float2(-1.07,1.2);
                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                float2 screenUV=i.positionCS.xy/_ScreenParams.xy;//屏幕空间下的UV的坐标
                //water depth
                half4 depthTex=SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV);
                half depthScene=LinearEyeDepth(depthTex,_ZBufferParams);
                half4 depthWater= depthScene + i.positionVS.z;//水的深度 ，摄像机距离太远导致相机精度不够，无法呈现真正的效果
                
                //water color
                half4 waterColor=lerp(_WaterColor02,_WaterColor01,depthWater);

                //water highlight —— blinn-phone  specularColor*Ks*pow(max(0,dot(N,H)),shininess) H=light+view
                //use normal make water surface shine
                half4 normalTex01=SAMPLE_TEXTURE2D(_NormalMap,sampler_NormalMap,i.normalUV.xy);
                half4 normalTex02=SAMPLE_TEXTURE2D(_NormalMap,sampler_NormalMap,i.normalUV.zw);
                half3 N=normalTex01*normalTex02;//不归一化会出现网格状，不丝滑
                Light light=GetMainLight();
                half3 L=light.direction;//light direction
                half3 V=saturate(_WorldSpaceCameraPos.xyz-i.positionWS.xyz);//view direction
                half3 H=saturate(L+V);
                half dotH=dot(N,H);
                half4 specular=_SpecularColor*_Specular*pow(max(0,dotH),_Smoothness);
                
                //water reflection
                half3 reflectionUV=reflect(-V,N);//反射方向
                half4 reflectionTex=SAMPLE_TEXTURECUBE(_ReflectionTex,sampler_ReflectionTex,reflectionUV);
                half fresnel=pow(1-saturate(dot(N,V)),3);
                half4 reflection=lerp(specular,reflectionTex*fresnel,_ReflectionDensity);
                
                
                //under water distort(use distort texture sample用噪波图进行采样)
                half4 distortText=SAMPLE_TEXTURE2D(_DistortMap,sampler_DistortMap,i.uv.zw);
                half2 distortUV=lerp(screenUV,distortText,_DistortDensity/10);
                half4 distortTex=SAMPLE_TEXTURE2D(_CameraOpaqueTexture,sampler_CameraOpaqueTexture,distortUV);
                half depthDistortScene=LinearEyeDepth(distortTex,_ZBufferParams);
                half depthDistortWater=depthDistortScene+i.positionVS.z;
                half2 opaqueUV=distortText;
                if (depthDistortWater<0) opaqueUV=screenUV;
                half4 opaqueTex=SAMPLE_TEXTURE2D(_CameraOpaqueTexture,sampler_CameraOpaqueTexture,opaqueUV);

                
                //water caustic scattering
                half4 depthVS=1;
                depthVS.xy=i.positionVS.xy*depthDistortScene/-i.positionVS.z;//用depthDistortScene产生焦散扭曲效果
                depthVS.z=depthDistortScene;
                half3 depthWS=mul(unity_CameraToWorld,depthVS);
                
                //加上y值引起偏移，防止在竖向上只有采样单个值
                half2 causticUV01=depthWS.xz*_Caustic_ST.xy+_Time.x*_Speed+depthWS.y*0.2;
                half4 causticTex01=SAMPLE_TEXTURE2D(_Caustic,sampler_Caustic,causticUV01);
                
                half2 causticUV02=depthWS.xz*_Caustic_ST.xy+_Time.x*_Speed*half2(-1.17,1.28)+depthWS.y*0.1;
                half4 causticTex02=SAMPLE_TEXTURE2D(_Caustic,sampler_Caustic,causticUV02);
                half4 caustic= min(causticTex01,causticTex02);
                //half atten=depthWater>_CausticRange? 0.2:depthWater;
                caustic*=_CausticDensity;
                //caustic*=atten;//衰减
                
                //water foam
                half foamRange= depthWater*_FoamRange;
                half foamTex=pow(SAMPLE_TEXTURE2D(_FoamTex,sampler_FoamTex,i.uv.xy),_FoamNoise);
                half foamMask= step(foamRange,foamTex);
                half4 foam=foamMask*_FoamColor;


                half4 c;
                c=foam+waterColor+opaqueTex+caustic*2+reflection;
                
                c.a=0.5;
                return c;
            }
            ENDHLSL
        }
    }
}
