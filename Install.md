# 安装
## 准备
+ 安装 docker ,helm3, kubectl
+ 可用的镜像仓库

## 配置
**ApisixTinyController** 采用 helm3 chart 方式管理
并提供了非常灵活的配置参数,用户可以在 deploy/helm/values.yaml中定义

## 执行
  ```shell
    make install -hub=${DockerHub}
  ```

## 使用
### 概念

1. 集群可以部署多个 **ApisixTinyController** ,每个 **ApisixTinyController** 可以分布在不同的Namespace ,

2. 每个 **ApisixTinyController** 在集群范围内都有互不冲突的名字(name)

3. 可以定义集群资源 apisix.apache.org/certs, 这些 certs 由所有 **ApisixTinyController** 共享读取

4. 可以定义集群资源 apisix.apache.org/configs, 
   这些 configs 代表 每个 **ApisixTinyController** 的全局配置(global_rules,plugins等)

5. 可以定义Namespaced 资源 apisix.apache.org/rules,
   每条 rules 必须 添加 apisix.apache.org/controller-by: ${ApisixTinyController.Name} 标签,
   用于表示 该 rules 由 哪个 **ApisixTinyController** 进行数据面代理.
   
### 示例
todo