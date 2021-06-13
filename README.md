# ApisixController
```text
  项目基于 Apisix 的一种　K8S Ingress Controller 实现.

  但本项目并不会支持
   networking.k8s.io/v1/ingress
   networking.k8s.io/v1beta1.ingress
   extensions/v1beta1.ingress
  
  因为,项目作者认为 ingress 需要大量非标准化的注解支持，并不具备生产可用性.


  本项目是用的规则是将　Apisix Stand Alone模式下的　apisix.yaml　配置格式转换成 K8S CRD 定义.
  
  这样用户不需要理解任何注解，就可以无缝使用 apisix提供的各种插件能力，包括开发的任何自定义插件

```
# 使用
  1. 安装 docker ,helm3, kubect
  2. 准备一个可用的镜像仓库　DockerHubAddress
  3. make install hub=${DockerHubAddress}

# 测试
  1. make test hub=${DockerHubAddress}