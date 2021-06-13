# ApisixController
```text
  本项目是以 apisix 为底层代理的一种 K8S Ingress Controller 实现.

  但本项目并不会支持
   networking.k8s.io/v1.ingress
   networking.k8s.io/v1beta1.ingress
   extensions/v1beta1.ingress
   
  因为,项目作者认为 ingress　定义的太简陋，以致于所有的 IngressController 都需要额外添加大量的注解才能实际投入使用．但注解规则与 IngressController 的绑定又完全背离的 Ingress 的抽象目标.
  项目作者认为　Ingress 是一个失败的试验品. 
  

  本项目也需要定义　CRD，但其特点在于:
  本项目定义的 CRD 是将　Apisix Stand Alone 模式下的　apisix.yaml　配置格式转换成 K8S CRD Schema, 这样，任何能在　apisix.yaml（apisix stand －alone　模式）中定义的的规则，都可以通过在　k8s　crd 资源中原样定义．
  这种使用方式的优点:
  　1. 不需要用户理解任何额外的注解规则
　　２．在 IngressController 中完全复用 Apisix 本身的能力, 包括任何自定义开发的插件
```
# 项目实现
  
  项目在实现上只有两个文件,分别为

  ## k8s.lua
  ```text
     k8s.lua 功能与　apisix 的其他　discovery 组件一样，用于在 k8s运行环境中动态发现后端节点．
     实现上是通过　list-watch  k8s v1.endpoints , 然后　将　节点变换信息写入  lua.shared.DICT 来实现的．
     k8s.lua 要求　upstream 的　service_name 格式为  [k8s service name]:[k8s service port name]
  ```

  ## controller.lua
 ```text
     controller.lua 是作为 apisix 的一个后台运行插件开发的．但只会由　特权进程启动．
     其功能是　list-watch k8s apisix.apache.org/v1alpha1.rules ,然后将其变换信息　写入　conf/apisix.yaml 文件,
     其他 worker 进程会定时主动读取 apisix.yaml,实现路由规则，插件的热更新
  ```

# CRD　定义
 ```text
    crd 定义 由 helm/crds/rules.yaml 文件描述
 ```

# 使用
  ## 准备
   + 安装 docker ,helm3, kubect
   + 准备可用的镜像仓库地址 DockerHubAddress

  ## 安装
  ```shell
    make install hub=${DockerHubAddress}
  ```
  ## 测试
  ```shell
    #测试需要安装 minikube ,用于模拟 k8s 集群
    
    make test hub=${DockerHubAddress}
  ```
 
# Todo List

1. 补全 CRD　定义,包括　global_rules, plugins 等
2. 测试用例
3. 文档
