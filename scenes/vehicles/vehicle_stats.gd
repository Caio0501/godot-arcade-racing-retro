class_name VehicleStats
extends Resource
## Propriedades de direção de um veículo. Crie um .tres por modelo e ligue no
## campo `stats` do Vehicle. A conversão para física fica em vehicle.gd, então
## um carro novo só precisa de valores diferentes aqui.

## Velocidade máxima que o carro alcança.
@export_range(40.0, 300.0, 1.0, "suffix:km/h") var top_speed := 120.0
## Quão bom de curva o carro é (1 = ruim, 10 = excelente). Define o ângulo e a
## rapidez do volante e o ponto em que os pneus da frente perdem aderência.
@export_range(1.0, 10.0, 0.1) var handling := 5.0
## Peso do carro. Mais pesado demora mais para chegar à velocidade máxima, mas
## é mais difícil de perder o controle (traseira mais firme, gira menos).
@export_range(600.0, 3000.0, 10.0, "suffix:kg") var weight := 1200.0
