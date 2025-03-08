Shader "taecg/URP/Depth Decal"
{
    //重建观察空间坐标
    //用cube更好,用面片的话，由于面片大小的影响，在一定视角下会有影响（裁剪掉一部分）
    Properties
    {
        _BaseColor("Base Color",color) = (1,1,1,1)
        _BaseMap("BaseMap", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Blend One One

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
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float fogCoord      : TEXCOORD1;
                float4 positionOS   : TEXCOORD2;
                float3 positionVS   : TEXCOORD3;    //顶点在观察空间下的坐标
            };

            CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float4 _BaseMap_ST;
            CBUFFER_END
            TEXTURE2D (_BaseMap);//SAMPLER(sampler_BaseMap);
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
            #define smp _linear_Repeat//使用_linear_Clamp则只采样一次
            SAMPLER(smp);

            Varyings vert(Attributes v)
            {
                Varyings o;

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                o.positionOS = v.positionOS;
                o.positionVS = TransformWorldToView(TransformObjectToWorld(v.positionOS));//从物体空间到世界空间再到观察空间
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                //思路：
                //通过深度图求出像素所在的观察空间中的Z轴
                //通过当前渲染的面片求出像素在观察空间下的坐标
                //通过以上两者求出深度图中的像素的XYZ坐标
                //再将此坐标转换面片模型的本地空间,把XY当作UV来进行纹理采样。

                float2 screenUV = i.positionCS.xy/_ScreenParams.xy;
                half depthMap = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV);
                half depthZ = LinearEyeDepth(depthMap,_ZBufferParams);//观察空间下的Z轴

                //构建深度图上的像素在观察空间下的坐标（顶点在观察空间下的坐标）
                float4 depthVS = 1;
                depthVS.xy = i.positionVS.xy*depthZ/-i.positionVS.z;
                depthVS.z = depthZ;
                //构建深度图上的像素在世界空间下的坐标  
                float3 depthWS = mul(unity_CameraToWorld,depthVS);//从观察空间到世界空间
                float3 depthOS = mul(unity_WorldToObject,float4(depthWS,1));//从世界空间到物体本体空间

                // return frac(depthOS.y);
                float2 uv = depthOS.xz + 0.5;
                //如果使用的时depthWS则会把整个世界空间移动到uv，基本找不到贴图
                //因为模型自己中心是0,0为了把贴花移动到中心，需要+0.5把图像放到中间
                half4 c;
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, smp, uv);
                c = baseMap * _BaseColor;

                //针对Blend One One的雾效混合方式，因为雾效的影响，面片的边缘会出现高亮
                c.rgb *= saturate(lerp(1,0,i.fogCoord));
                //lerp(1,0,i.fogCoord)当雾效较小时显示贴花自己的颜色，较大时出现半透明效果，逐渐受到雾效的影响
                return c;
            }
            ENDHLSL
        }
    }
//buildin 管线
//    SubShader
//    {
//        Tags { "Queue"="Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
//        LOD 100
//
//        Pass
//        {
//            Blend One One
//
//            Name "Unlit"
//            HLSLPROGRAM
//            // Required to compile gles 2.0 with standard srp library
//            #pragma prefer_hlslcc gles
//            #pragma exclude_renderers d3d11_9x
//            #pragma vertex vert
//            #pragma fragment frag
//            #pragma multi_compile_fog
//            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
//            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
//            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
//
//            struct Attributes
//            {
//                float4 positionOS       : POSITION;
//                float2 uv               : TEXCOORD0;
//            };
//
//            struct Varyings
//            {
//                float4 positionCS       : SV_POSITION;
//                float2 uv           : TEXCOORD0;
//                float fogCoord      : TEXCOORD1;
//                float4 positionOS   : TEXCOORD2;
//                float3 positionVS   : TEXCOORD3;    //顶点在观察空间下的坐标
//            };
//
//            CBUFFER_START(UnityPerMaterial)
//            half4 _BaseColor;
//            float4 _BaseMap_ST;
//            CBUFFER_END
//            TEXTURE2D (_BaseMap);//SAMPLER(sampler_BaseMap);
//            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
//            #define smp _linear_clamp
//            SAMPLER(smp);
//
//            Varyings vert(Attributes v)
//            {
//                Varyings o = (Varyings)0;
//
//                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
//                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
//                o.fogCoord = ComputeFogFactor(o.positionCS.z);
//                o.positionOS = v.positionOS;
//                o.positionVS = TransformWorldToView(TransformObjectToWorld(v.positionOS));
//                return o;
//            }
//
//            half4 frag(Varyings i) : SV_Target
//            {
//                //思路：
//                //通过深度图求出像素所在的观察空间中的Z轴
//                //通过当前渲染的面片求出像素在观察空间下的坐标
//                //通过以上两者求出深度图中的像素的XYZ坐标
//                //再将此坐标转换面片模型的本地空间,把XY当作UV来进行纹理采样。
//
//                float2 screenUV = i.positionCS.xy/_ScreenParams.xy;
//                half depthMap = SAMPLE_TEXTURE2D(_CameraDepthTexture,sampler_CameraDepthTexture,screenUV);
//                half depthZ = LinearEyeDepth(depthMap,_ZBufferParams);
//
//                //构建深度图上的像素在观察空间下的坐标
//                float4 depthVS = 1;
//                depthVS.xy = i.positionVS.xy*depthZ/-i.positionVS.z;
//                depthVS.z = depthZ;
//                //构建深度图上的像素在世界空间下的坐标
//                float3 depthWS = mul(unity_CameraToWorld,depthVS);
//                float3 depthOS = mul(unity_WorldToObject,float4(depthWS,1));
//
//                // return frac(depthOS.y);
//                float2 uv = depthOS.xz + 0.5;
//
//                half4 c;
//                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, smp, uv);
//                c = baseMap * _BaseColor;
//
//                //针对Blend One One的雾效混合方式
//                c.rgb *= saturate(lerp(1,0,i.fogCoord));
//                return c;
//            }
//            ENDHLSL
//        }
//    }
//    Fallback "Diffuse"
}
