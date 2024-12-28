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
    prod = {
      name    = "microstore"
      type    = "CNAME"
      ttl     = 300
      records = []
    }
  }
} 