# aws-network Hub/spoke com transit gateway

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

[[transit_hub_spoke.png]]


------------

Apenas uma unica conta AWS

10.21.0.0/20 -> Public(Nat)
10.21.16.0/20 -> App
10.21.32.0/20 -> Data
10.21.96.0/20 -> Firewall

rt-private (subnets data e app)
10.21.0.0/16 -> local
0.0.0.0/0 -> Nat


rt-public(subnet public)
0.0.0.0/0 -> vpce-firewall
10.21.0.0/16

rt-internet-gateway(vincular o internet gateway na aba edge associations)
10.21.0.0/20 -> vpce-firewall
10.21.0.0/16 -> local

[[network_firewall.png]]



