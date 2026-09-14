- rolearn: ${node_role_arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups: ["system:bootstrappers", "system:nodes"]
- rolearn: ${cd_role_arn}
  username: cd-${cluster_name}
  groups: ["system:masters"]
