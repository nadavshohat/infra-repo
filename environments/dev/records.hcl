inputs = {
  zone_name = "nshohat.online"
  
  route53_records = {
    argocd = {
      name    = "argocd"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
    grafana = {
      name    = "grafana"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
    prometheus = {
      name    = "prometheus"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
    dev = {
      name    = "dev"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
    kibana = {
      name    = "kibana"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
  }
} 