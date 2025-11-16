# Recommended Learning Resources

Curated resources for continuing your Kubernetes, AWS EKS, and DevOps learning journey.

---

## Official Documentation

### Kubernetes

**📚 [Kubernetes Documentation](https://kubernetes.io/docs/)**
- Comprehensive official documentation
- Start with "Concepts" section
- Excellent reference material

**📖 [Kubernetes Tasks](https://kubernetes.io/docs/tasks/)**
- Step-by-step guides for specific tasks
- Great for learning by doing

**🎓 [Kubernetes Tutorials](https://kubernetes.io/docs/tutorials/)**
- Structured learning paths
- Covers beginner to advanced topics

### AWS EKS

**📚 [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)**
- Official AWS EKS guide
- Integration with AWS services

**📖 [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)**
- **HIGHLY RECOMMENDED**
- Covers security, networking, scalability, observability
- Based on real-world AWS experience

**🎓 [AWS Workshops - EKS](https://eksworkshop.com/)**
- Hands-on labs and tutorials
- Free, self-paced learning

### Pulumi

**📚 [Pulumi Documentation](https://www.pulumi.com/docs/)**
- Complete Pulumi reference
- Examples in multiple languages

**📖 [Pulumi Examples](https://github.com/pulumi/examples)**
- Real-world infrastructure examples
- Kubernetes, AWS, and more

**🎓 [Pulumi Learn](https://www.pulumi.com/learn/)**
- Guided tutorials
- Pulumi fundamentals

---

## Books

### Kubernetes

**📗 Kubernetes Up & Running** by Brendan Burns, Joe Beda, Kelsey Hightower
- Excellent introduction to Kubernetes
- Covers core concepts thoroughly
- Regularly updated

**📗 Kubernetes in Action** by Marko Lukša
- Deep dive into Kubernetes internals
- Comprehensive and detailed
- Good for intermediate learners

**📗 Production Kubernetes** by Josh Rosso, Rich Lander, Alex Brand, John Harris
- Focuses on running K8s in production
- Covers Day 2 operations
- Advanced topics

### DevOps and Cloud-Native

**📗 The DevOps Handbook** by Gene Kim, Patrick Debois, John Willis, Jez Humble
- DevOps principles and practices
- Real-world case studies
- Culture and processes

**📗 Cloud Native DevOps with Kubernetes** by John Arundel, Justin Domingus
- Kubernetes best practices
- CI/CD and GitOps
- Production considerations

**📗 Site Reliability Engineering** (Google)
- Free online: https://sre.google/books/
- SRE principles and practices
- Production reliability patterns

---

## Online Courses

### Kubernetes

**🎓 [Kubernetes for Developers (LFD259)](https://training.linuxfoundation.org/training/kubernetes-for-developers/)**
- Linux Foundation official course
- Hands-on labs
- Certification preparation

**🎓 [Certified Kubernetes Administrator (CKA)](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)**
- Industry-recognized certification
- Hands-on exam
- Validates Kubernetes skills

**🎓 [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)**
- Learn K8s by building from scratch
- Understand every component
- Advanced, but excellent learning

### AWS

**🎓 [AWS Skill Builder](https://skillbuilder.aws/)**
- Free AWS training
- EKS courses available
- Certification preparation

**🎓 [A Cloud Guru - AWS Courses](https://acloudguru.com/)**
- Comprehensive AWS training
- EKS and container courses
- Hands-on labs

---

## Interactive Learning

**🎮 [Kubernetes By Example](https://kubernetesbyexample.com/)**
- Quick, practical examples
- Copy-paste ready commands
- Great reference

**🎮 [Play with Kubernetes](https://labs.play-with-k8s.com/)**
- Free browser-based Kubernetes cluster
- 4 hours of playtime
- No installation needed

**🎮 [Katacoda Kubernetes Scenarios](https://www.katacoda.com/courses/kubernetes)**
- Interactive browser-based tutorials
- Step-by-step guidance
- Various difficulty levels

**🎮 [KillerCoda](https://killercoda.com/)**
- Successor to Katacoda
- Interactive Kubernetes scenarios
- Free hands-on practice

---

## Blogs and Newsletters

### Kubernetes

**📰 [Kubernetes Blog](https://kubernetes.io/blog/)**
- Official Kubernetes news
- Release announcements
- Community updates

**📰 [CNCF Blog](https://www.cncf.io/blog/)**
- Cloud Native Computing Foundation
- Kubernetes ecosystem news
- Project updates

### AWS

**📰 [AWS Containers Blog](https://aws.amazon.com/blogs/containers/)**
- EKS updates and best practices
- Container-related AWS news
- Technical deep dives

**📰 [AWS Architecture Blog](https://aws.amazon.com/blogs/architecture/)**
- AWS solution architectures
- Best practices
- Real-world case studies

### DevOps and SRE

**📰 [Google Cloud Blog - SRE](https://cloud.google.com/blog/products/devops-sre)**
- SRE principles and practices
- Reliability engineering
- Production operations

**📰 [The New Stack](https://thenewstack.io/)**
- Cloud-native technologies
- Kubernetes and containers
- DevOps trends

---

## Tools and Utilities

### kubectl Plugins

**🔧 [krew](https://krew.sigs.k8s.io/)**
- kubectl plugin manager
- Install plugins easily
- Extend kubectl functionality

**🔧 Popular kubectl plugins:**
```bash
# Install krew first, then:
kubectl krew install ctx      # Switch contexts
kubectl krew install ns       # Switch namespaces
kubectl krew install tree     # Show resource hierarchy
kubectl krew install stern    # Multi-pod log tailing
```

### Cluster Management

**🔧 [k9s](https://k9scli.io/)**
- Terminal UI for Kubernetes
- Navigate cluster visually
- View logs, describe resources

**🔧 [Lens](https://k8slens.dev/)**
- Kubernetes IDE
- Visual cluster management
- Free and open source

**🔧 [kubectl-ai](https://github.com/sozercan/kubectl-ai)**
- Generate K8s manifests with AI
- Natural language to YAML
- Experimental but useful

### CI/CD and GitOps

**🔧 [ArgoCD](https://argo-cd.readthedocs.io/)**
- Declarative GitOps
- Automatic sync from Git
- Visual UI

**🔧 [Flux](https://fluxcd.io/)**
- GitOps toolkit
- Git as source of truth
- Automatic reconciliation

**🔧 [Tekton](https://tekton.dev/)**
- Cloud-native CI/CD
- Kubernetes-native pipelines
- Flexible and extensible

### Security

**🔧 [Trivy](https://aquasecurity.github.io/trivy/)**
- Vulnerability scanner
- Scan containers, IaC, config files
- Free and fast

**🔧 [Falco](https://falco.org/)**
- Runtime security
- Detect anomalous activity
- CNCF project

**🔧 [Kubescape](https://kubescape.io/)**
- Kubernetes security platform
- Scan clusters for vulnerabilities
- NSA/CISA hardening guide

---

## GitHub Repositories to Study

### Example Projects

**📂 [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)**
- Complete microservices application
- Kubernetes manifests included
- Good reference architecture

**📂 [kubernetes/examples](https://github.com/kubernetes/examples)**
- Official Kubernetes examples
- Various use cases
- Well-documented

### Infrastructure as Code

**📂 [pulumi/examples](https://github.com/pulumi/examples)**
- Pulumi infrastructure examples
- Multiple cloud providers
- Various languages

**📂 [terraform-aws-modules](https://github.com/terraform-aws-modules)**
- Reusable Terraform modules
- AWS best practices
- Well-maintained

---

## Community and Support

### Forums and Q&A

**💬 [Kubernetes Slack](https://kubernetes.slack.com/)**
- Official Kubernetes Slack
- Ask questions, get help
- Active community

**💬 [Stack Overflow - Kubernetes](https://stackoverflow.com/questions/tagged/kubernetes)**
- Q&A for specific problems
- Search before asking
- Help others learn

**💬 [Reddit - r/kubernetes](https://www.reddit.com/r/kubernetes/)**
- Kubernetes discussions
- News and tutorials
- Community support

### Conferences and Events

**🎤 [KubeCon + CloudNativeCon](https://www.cncf.io/kubecon-cloudnativecon-events/)**
- Largest Kubernetes conference
- Multiple events per year
- Recordings available on YouTube

**🎤 [AWS re:Invent](https://reinvent.awsevents.com/)**
- Annual AWS conference
- EKS and container sessions
- Hands-on workshops

---

## Video Content

### YouTube Channels

**📺 [TechWorld with Nana](https://www.youtube.com/@TechWorldwithNana)**
- Kubernetes and DevOps tutorials
- Clear explanations
- Beginner-friendly

**📺 [That DevOps Guy](https://www.youtube.com/@MarcelDempers)**
- Practical DevOps content
- Kubernetes deep dives
- Production-focused

**📺 [CNCF](https://www.youtube.com/@cncf)**
- KubeCon talk recordings
- Project demos
- Technical deep dives

**📺 [AWS Events](https://www.youtube.com/@AWSEventsChannel)**
- re:Invent sessions
- EKS and container content
- Technical workshops

### Specific Video Series

**📺 [Kubernetes Tutorial for Beginners](https://www.youtube.com/watch?v=X48VuDVv0do)** - TechWorld with Nana
- 4-hour comprehensive tutorial
- Covers fundamentals
- Hands-on examples

**📺 [EKS Workshop](https://www.youtube.com/playlist?list=PLhr1KZpdzukf1ERxT5b6N9J5hLyjqQxfK)** - AWS
- Official AWS workshop
- Step-by-step guidance
- Free and complete

---

## Cheat Sheets and Quick References

**📋 [Kubernetes Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)**
- Official kubectl cheat sheet
- Common commands
- Quick reference

**📋 [AWS EKS Cheat Sheet](https://github.com/dennyzhang/cheatsheet-kubernetes-A4)**
- EKS-specific commands
- AWS CLI examples
- Troubleshooting tips

**📋 [Docker Cheat Sheet](https://docs.docker.com/get-started/docker_cheatsheet.pdf)**
- Container basics
- Docker commands
- Quick reference

---

## Podcasts

**🎙️ [Kubernetes Podcast from Google](https://kubernetespodcast.com/)**
- Weekly Kubernetes news
- Interviews with contributors
- Community updates

**🎙️ [The Cloudcast](https://www.thecloudcast.net/)**
- Cloud computing topics
- Industry news
- Expert interviews

**🎙️ [AWS Podcast](https://aws.amazon.com/podcasts/aws-podcast/)**
- AWS news and updates
- Customer stories
- Technical discussions

---

## Practice and Challenges

**🏆 [CKA/CKAD Practice](https://github.com/dgkanatsios/CKAD-exercises)**
- Kubernetes certification practice
- Hands-on exercises
- Various difficulty levels

**🏆 [Kubernetes Security Challenges](https://securekubernetes.com/)**
- Security-focused challenges
- Learn by exploiting and fixing
- Advanced topics

**🏆 [Advent of Code](https://adventofcode.com/)**
- Not Kubernetes-specific
- Great for sharpening coding skills
- Fun challenges

---

## Next Steps from This Project

Based on what you've learned in this project, here's a suggested learning path:

### Immediate (Next 1-2 weeks)
1. ✅ Complete the EKS Workshop (https://eksworkshop.com/)
2. ✅ Read AWS EKS Best Practices Guide (security and networking sections)
3. ✅ Experiment with ArgoCD or Flux for GitOps

### Short-term (Next 1-2 months)
1. ✅ Take Kubernetes for Developers (LFD259) course
2. ✅ Read "Kubernetes Up & Running" book
3. ✅ Build a multi-service application on EKS
4. ✅ Implement proper secrets management (External Secrets Operator)

### Medium-term (Next 3-6 months)
1. ✅ Study for CKA or CKAD certification
2. ✅ Read "Production Kubernetes" book
3. ✅ Implement observability stack (Prometheus + Grafana)
4. ✅ Contribute to open-source Kubernetes projects

### Long-term (Next 6-12 months)
1. ✅ Get CKA or CKAD certified
2. ✅ Read SRE books from Google
3. ✅ Build production-ready systems at work
4. ✅ Share knowledge through blog posts or talks

---

## How to Stay Current

Kubernetes and cloud-native technologies evolve rapidly. To stay current:

1. **Follow release notes** - Kubernetes releases every ~4 months
2. **Join the community** - Slack, forums, meetups
3. **Read blogs** - AWS Containers Blog, CNCF Blog
4. **Watch KubeCon talks** - Free on YouTube
5. **Experiment** - Try new tools and features
6. **Build projects** - Apply what you learn
7. **Share knowledge** - Write, speak, teach

---

**Remember:** You don't need to learn everything at once. Pick one area to focus on, go deep, then expand to the next area. The fundamentals you learned in this project will serve you throughout your journey!
