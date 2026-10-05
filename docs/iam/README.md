# Terraform operator permissions

## Initial plan reads

The first real AWS plan authenticated successfully but stopped at two data-source reads:

- `ec2:DescribeAvailabilityZones`: discover an available zone in Sydney.
- `ssm:GetParameter`: read the public Amazon Linux 2023 x86_64 AMI parameter.

`terraform-initial-plan-read.json` addresses only these observed denials. It grants no resource creation, modification or deletion permissions. It is not a complete policy for Terraform apply/destroy or for refreshing existing deployed resources. After attaching it, rerun plan and review any further permission errors before extending access.

An account administrator can create a customer managed IAM policy named `TerraformDemoInitialPlanRead` using this JSON, then attach it to `terraform-demo-user` or its group. Keep `SignInLocalDevelopmentAccess` attached as well; that policy enables CLI login, while this policy permits the two AWS API reads. The development user cannot grant itself permissions.

The SSM ARN deliberately has an empty account-ID field because the parameter is AWS public data. Do not insert your account ID there. The availability-zone query has no individual resource ARN, so its statement uses `Resource: "*"` with a Sydney region condition.

These policies are administrator bootstrap steps outside the application's Terraform state. The instance role defined in `terraform/iam.tf` is separate: that role is for the EC2 instance's SSM Agent.

After attaching the initial read policy, the real plan succeeded: **13 to add, 0 to change, 0 to destroy**, in `ap-southeast-2`. After the two lifecycle policies below were attached, the first apply created all 13 resources successfully, and a subsequent plan reported no changes. Destroy permissions have not yet been verified.

## 部署与清理策略：需要管理员附加

使用具有 IAM 管理权限的身份创建以下两份客户托管策略。当前开发用户不能为自己创建或附加策略。

1. `TerraformDemoEC2Lifecycle`：复制 [terraform-ec2-lifecycle.json](terraform-ec2-lifecycle.json) 的完整内容。
2. `TerraformDemoInstanceIAM`：复制 [terraform-instance-iam.json](terraform-instance-iam.json) 的完整内容。

每份策略的操作入口相同：**IAM → Policies → Create policy → JSON → 粘贴内容 → Next → 填写上述名称 → Create policy**。审阅控制台的策略校验结果后创建。

再进入 **IAM → Users → terraform-demo-user → Permissions → Add permissions → Attach policies directly**，搜索并选中这两份策略，完成附加。保留已有的 `SignInLocalDevelopmentAccess` 和 `TerraformDemoInitialPlanRead`。

这两份部署策略已使用当前账户 ID `828874705787`，可直接复制到该账户的 IAM 控制台。用于其他账户时，替换这个 12 位账户 ID。`Resource` ARN 的账户段不能使用 `${aws:PrincipalAccount}` 等策略变量；变量只能出现在第五个冒号之后的资源部分，旧写法会导致 `The policy failed legacy parsing`。公共 AMI、公共 SSM 参数 ARN 中的空账户段，以及 AWS 托管策略 ARN 中的 `aws`，应保持原样。

### TerraformDemoEC2Lifecycle 的范围

- 允许读取 Sydney 区域的 EC2 元数据；这类读取未按项目标签过滤，会包含该区域其他资源的元数据。
- 创建 VPC、子网、路由表、安全组、规则和 Internet Gateway 时，要求 `Project=terraform-cloud-platform-demo` 标签；创建子资源所用的 VPC 也必须带该标签。
- 管理和删除操作要求目标资源已有项目标签。打标签权限不能给无关资源补上该标签，也不能修改或移除已有的 `Project` 标记。
- 启动实例时只允许 `t3.micro` / `t3.small`、默认租用模式、IMDSv2 和项目实例配置文件；磁盘必须有项目标签、启用加密，使用不超过 8 GiB 的 gp3 卷。
- AMI 固定为本次真实 plan 解析出的 `ami-0720cb7af233b0529`。Terraform 的公共 AMI 参数以后可能变化；届时需先审阅新 AMI，再由管理员更新策略中的 `UseReviewedAmi`。
- `RunInstances` 分别校验镜像、实例、卷、网卡、子网和安全组。新主网卡尚无标签，因此单独允许在同账户、同区域的网卡资源上执行 `RunInstances`；同一次调用还必须满足项目子网和安全组的限制。未授权独立创建网卡。
- 包含删除及解绑操作，供 Terraform 清理资源；没有授予 EC2 全部写权限，也没有启用 Spot、NAT Gateway 或 Elastic IP 创建权限。

这份策略针对当前单实例配置的首次创建、刷新、替换和清理，不覆盖任意未来配置变更。例如更换已有实例的类型、原地修改磁盘或切换环境名时，应先重新核对所需权限。实例数量不受此策略限制，标签和实例类型限制也不是费用上限。

### TerraformDemoInstanceIAM 的范围

- 仅管理同账户 `terraform-demo-dev-` 前缀的角色与实例配置文件。
- 角色只能附加或解绑 `AmazonSSMManagedInstanceCore` 托管策略。
- `iam:PassRole` 仅允许把这些角色交给 `ec2.amazonaws.com`。
- 不允许创建 IAM 用户、创建托管策略、写入内联角色策略，或给自己附加权限。

请将此命名前缀专用于本项目，不要让现有高权限角色使用该前缀。IAM 管理权限按前缀而非标签限制；它不是用于不可信多租户的权限隔离方案。IAM 权限是累加的，其他已附加策略可能扩大实际权限。

实例角色的 SSM 权限让 Agent 注册和连接服务；它不自动授予开发用户 `ssm:StartSession`。需要人工开启 SSM 会话时，应另行配置针对项目实例的会话权限。

### 已做的检查与后续验证

- 已检查 ARN 的账户段：使用实际账户 ID，保留 AWS 公共资源所需的空账户段及 AWS 托管策略的 `aws` 账户段。
- 两份 JSON 均已解析校验，非空白字符数均低于每份客户托管策略的 6,144 字符限制。
- 已对照 AWS 官方机器可读权限参考核对 action 名称及服务专用 condition keys。
- 已核对锁定的 AWS provider 6.67.0：创建实例时将 provider 的默认标签应用于实例和 EBS 卷，匹配策略中的创建标签条件。
- 两份部署策略附加后，真实 apply 成功创建全部 13 项资源，随后 plan 返回零变更，验证了当前配置的首次创建和刷新权限。尚未通过 AWS IAM Access Analyzer / Policy Simulator 完整验证，替换及 destroy 权限也尚未实测；不能将首次创建成功当作所有生命周期权限已通过。
- 本地 `terraform.tfvars`、state 和 `.tfplan` 文件不提交。保留 state 直到清理成功；失败的 apply 也可能留下资源，不应删除 state 后重新开始。

## References

- [Where IAM policy variables can be used](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html#policy-vars-using)

- [Create an IAM policy in the console](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_create-console.html)
- [EC2 action/resource authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html)
- [IAM action/resource authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_iam.html)
- [Tagging EC2 resources during creation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/supported-iam-actions-tagging.html)
- [IAM condition keys including PassRole and PolicyARN](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html)
- [Machine-readable AWS service reference](https://docs.aws.amazon.com/service-authorization/latest/reference/service-reference.html)
- [AWS provider 6.67.0 instance implementation](https://github.com/hashicorp/terraform-provider-aws/blob/v6.67.0/internal/service/ec2/ec2_instance.go)
