Peatio::Blockchain.registry[:bitcoin] = Bitcoin::Blockchain.new
Peatio::Blockchain.registry[:nexbit] = Nexbit::Blockchain.new
#Peatio::Blockchain.registry[:ndc] = Ndc::Blockchain.new
Peatio::Blockchain.registry[:geth] = Ethereum::Blockchain.new
Peatio::Blockchain.registry[:parity] = Ethereum::Blockchain.new


