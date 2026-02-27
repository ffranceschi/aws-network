# aws-network

Criada contas hub
vpc = 10.0.0.0/16

rt-att
0.0.0.0/16 -> tgw-att


Criada conta spoke dev
vpc = 10.10.0.0/16

rt-workload
10.0.0.0/16 -> tgw-att
0.0.0.0/16 -> tgw-att

rt-att
0.0.0.0/0 -> tgw-att


Criada conta spoke prod (identico ao dev)
vpc = 10.11.0.0/16

rt-att
0.0.0.0/0 -> vpce-(firewall)

rt-fw
0.0.0.0/0 -> nat-gateway
10.10.0.0/16 -> tgw

rt-public
10.0.0.0/16 -> local
10.10.0.0/16 -> vpce-(firewall)
0.0.0.0/0 -> igw

Adicionar a rota static no TGW 
0.0.0.0/0 -> tgw