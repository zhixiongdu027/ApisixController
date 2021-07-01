# ApisixTinyController

**ApisixTinyController** 是以 **Apache APISIX** 为底层代理的一种轻量,精简但能全面释放 **Apache APISIX** 能力的 K8S Ingress Controller 实现

## 特性

**ApisixTinyController** 不支持:

+ networking.k8s.io/v1.ingress
+ networking.k8s.io/v1beta1.ingress
+ extensions/v1beta1.ingress

原因是 **Ingress** 定义太过简陋以至于任何一个实际生产使用的 **Ingress Controller** 需要定义大量私有注解. 私有注解又使得**K8S Ingress** 丧失了统一性,移植性优势,进一步消解了 **
Ingress** 的价值. 作者认为支持 **Ingress** 只是**政治正确**.

**ApisixTinyController** 使用 **K8S CRD** 作为用户配置路由,证书,服务地址入口.

## 优势

**ApisixTinyController** 的优势为:
1. 实现精简,仅有三个实现文件
   + discovery/k8s.lua
   + plugins/controller.lua
   + plugins/webhook.lua 
   
2. CRD schema 与 **Apache APISIX** Schema 一一对应,带来了使用上的优势
   + 可以将 **Apache APISIX** 完整(stand_alone 模式支持的)能力复制到 **ApisixTinyController**
   + 可以兼容任何自研/第三方 **Apache APISIX** 插件
   + 可以校验任何自研/第三方 **Apache APISIX** 插件配置

## 实现

**ApisixTinyController** 的核心逻辑

### controller.lua
```text
  controller 通过 k8s apiserver 监听:
    apisix.apache.org/rules
    apisix.apache.org/configs
    apisix.apache.org/certs
  的实时变动,并将完整信息写入　conf/apisix.yaml文件
  worker 进程会定时主动读取 conf/apisix.yaml,实现路由规则,插件,证书的热更新
  
  controller.lua 只会由特权进程启动.
```

### k8s.lua
```text
  k8s.lua 与其他 discovery 插件一样,用于在k8s运行环境中动态发现后端节点,并为work进程提供查询接口.
  k8s.lua 通过 k8s apiserver 监听 endpoints 的实时变动,并将信息写入 lua shared DICT
  k8s.lua 提供 nodes(service_name) 接口供工作线程查询后端节点(nodes)
 
  k8s.lua 只会在特权进程启动监听, 在Work进程只提供查询功能
```

### webhook.lua
```text
  webhook.lua 在每个 work 进程提供了一个 http handle,用于校验 crd 对象 ,包括 crd 对象包含的 plugin config
  webhook.lua 提供的 handle 服务使用独立于业务服务端口,不会影响到业务服务.
```

## 测试
### 准备
   + 安装 docker ,helm3, kubectl
   + 安装 minikube用于模拟 k8s 集群 
   + 可用的镜像仓库

### 执行
 ```shell
    make test hub=${HubAddress}
 ```

# Todo List
1. 测试用例
2. 文档
3. Bug检测