# ApisixController

```text
  本项目是以 apisix 为底层代理的一种 K8S Ingress Controller 实现
  
  但本项目并不会支持
   networking.k8s.io/v1.ingress
   networking.k8s.io/v1beta1.ingress
   extensions/v1beta1.ingress
   
  原因是 Ingress 定义的太简陋,以致于所有的 IngressController 都需要额外添加大量的注解才能实际投入使用.
  但注解规则与 IngressController 的绑定又背离的Ingress 的抽象目标.
  
  本项目也需要定义 CRD,但其特点在于 CRD 是又 Apisix Stand Alone 模式下的 Apisix.yaml　配置格式
  对应转换而来.
  这样,任何能在 Apisix.yaml(Apisix Stand-Alone模式)中定义的的规则,都可以通过在 K8S 中资源中原样定义．
  
  其优点:
   1. 不需要用户理解任何额外的注解规则
　　2. 能完全复用 Apisix 能力,包括自定义开发的插件
```

# 项目实现

项目功能由两个文件实现:

## k8s.lua

  ```text
  k8s.lua 与　apisix 的其他 discovery 插件一样,用于在 k8s运行环境中动态发现后端节点．
  
  其实现原理是由任务线程　list-watch  k8s v1.endpoints, 并将其变换信息写入 ngx.shared.discovery 中,
  并提供　nodes(service_name) 函数供　工作线程查询后端节点(nodes)
  
  k8s.lua 要求 service_name 格式为 [k8s service name]:[k8s service port name]
  ```

## controller.lua

 ```text
  controller.lua 只会由特权进程启动．
  其实现原理是由任务线程　list-watch k8s apisix.apache.org/v1alpha1.rules ,并将其变换信息写入　conf/apisix.yaml 文件,
  其他 worker 进程会定时主动读取 apisix.yaml,实现路由规则,插件的热更新
 ```

# CRD

 ```text
  crd 由 helm/crds/rules.yaml 文件描述
 ```

# 使用

## 准备

+ 安装 docker ,helm3, kubect
+ 准备可用的镜像仓库

## 安装

  ```shell
    make install hub=${HubAddress}
  ```

## 测试

  ```shell
    #测试需要安装 minikube ,用于模拟 k8s 集群
    
    make test hub=${HubAddress}
  ```

# Todo List

1. 补全 CRD 定义,包括 global_rules, plugins 等
2. 测试用例
3. 文档
