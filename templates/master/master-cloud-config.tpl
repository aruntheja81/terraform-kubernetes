#cloud-config

---
coreos:
  update:
    reboot-strategy: etcd-lock
  locksmith:
    etcd_cafile: /etc/etcd/ssl/ca.pem
    etcd_certfile: /etc/etcd/ssl/client.pem
    etcd_keyfile: /etc/etcd/ssl/client-key.pem
    endpoint: ${endpoints}
  etcd2:
    data-dir: /media/etcd/etcd2
    election-timeout: 1200
    advertise-client-urls: https://${master_num}.master.k8s-${project}-${environment}.internal:2379
    initial-advertise-peer-urls: https://${master_num}.master.k8s-${project}-${environment}.internal:2380
    initial-cluster-state: new
    initial-cluster-token: int-test-k8s-master-token-1
    listen-client-urls: https://${master_num}.master.k8s-${project}-${environment}.internal:2379,https://127.0.0.1:2379
    listen-peer-urls: https://${master_num}.master.k8s-${project}-${environment}.internal:2380
    cert-file: /etc/etcd/ssl/server.pem
    client-cert-auth: true
    peer-client-cert-auth: true
    discovery-srv: etcd2.k8s-${project}-${environment}.internal
    key-file: /etc/etcd/ssl/server-key.pem
    peer-cert-file: /etc/etcd/ssl/peer.pem
    peer-key-file: /etc/etcd/ssl/peer-key.pem
    peer-trusted-ca-file: /etc/etcd/ssl/ca.pem
    trusted-ca-file: /etc/etcd/ssl/ca.pem

  units:
  - name: media-etcd.mount
    enable: true
    command: start
    content: |
      [Unit]
      Before=etcd2.service etcd3.service
      Description = Mount for Etcd Storage
      [Install]
      RequiredBy=etcd2.service etcd3.service
      WantedBy=multi-user.target
      [Mount]
      What=/dev/xvdh
      Where=/media/etcd
      Type=ext4
  - name: etcd2.service
    command: start
  - name: etcd3.service
    enable: true
    command: start
    content: |
     [Unit]
     Description=etcd3
     [Service]
     Slice=machine.slice
     KillMode=mixed
     ExecStartPre=/usr/bin/mkdir -p /media/etcd/etcd3
     ExecStartPre=/usr/bin/rkt trust --prefix "coreos.com/etcd" --skip-fingerprint-review
     ExecStart=/usr/bin/rkt run \
      --net=host \
      --volume=resolv,kind=host,source=/etc/resolv.conf \
      --mount volume=resolv,target=/etc/resolv.conf \
      --volume data-dir,kind=host,source=/media/etcd/etcd3 \
      --mount volume=data-dir,target=/var/lib/etcd3 coreos.com/etcd:v3.0.15 \
      -- \
      --data-dir /var/lib/etcd3 \
      --advertise-client-urls http://${master_num}.master.k8s-${project}-${environment}.internal:2389 \
      --initial-advertise-peer-urls http://${master_num}.master.k8s-${project}-${environment}.internal:2390 \
      --listen-client-urls http://0.0.0.0:2389 \
      --listen-peer-urls http://0.0.0.0:2390 \
      --discovery-srv etcd3.k8s-int-test.internal \
      --initial-cluster-state new \
      --initial-cluster-token etcd3-token-1
     Restart=always
     RestartSec=0
     LimitNOFILE=40000
     [Install]
     WantedBy=multi-user.target
  - name: manifest-copy.service
    command: start
    content: |
      [Unit]
      Description=AWS S3 Copy
      After=docker.service
      Requires=docker.service
      [Service]
      TimeoutStartSec=0
      Type=simple
      Restart=always
      RestartSec=10
      ExecStartPre=/usr/bin/docker pull mesosphere/aws-cli
      ExecStartPre=/usr/bin/docker run --rm -e "AWS_DEFAULT_REGION=eu-west-1" -v /etc/kubernetes:/project mesosphere/aws-cli \
        s3 cp --recursive s3://${project}-${environment}-k8s-data/pki/kubernetes/ pki/
      ExecStart=/usr/bin/docker run --rm -e "AWS_DEFAULT_REGION=eu-west-1" -v /etc/kubernetes:/project mesosphere/aws-cli \
        s3 cp --recursive s3://${project}-${environment}-k8s-data/manifests/master/${master_num}.master/ manifests/
      [Install]
      WantedBy=multi-user.target
      RequiredBy=kubelet.service
  - name: kubelet.service
    command: start
    enable: true
    content: |
      [Service]
      ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
      ExecStartPre=/usr/bin/mkdir -p /var/log/containers

      Environment=KUBELET_VERSION=${k8s_version}
      Environment="RKT_OPTS=--volume var-log,kind=host,source=/var/log \
      --mount volume=var-log,target=/var/log \
      --volume dns,kind=host,source=/etc/resolv.conf \
      --mount volume=dns,target=/etc/resolv.conf"

      ExecStart=/usr/lib/coreos/kubelet-wrapper \
      --api-servers=http://127.0.0.1:8080 \
      --network-plugin-dir=/etc/kubernetes/cni/net.d \
      --network-plugin= \
      --register-schedulable=false \
      --allow-privileged=true \
      --config=/etc/kubernetes/manifests \
      --cluster-dns=10.100.0.2 \
      --cluster-domain=k8s-${project}-${environment}.internal
      Restart=always
      RestartSec=10
      [Install]
      WantedBy=multi-user.target
  - name: docker-tcp.socket
    command: start
    enable: true
    content: |
      [Unit]
      Description=Docker Socket for the API

      [Socket]
      ListenStream=2375
      Service=docker.service
      BindIPv6Only=both

      [Install]
      WantedBy=sockets.target
