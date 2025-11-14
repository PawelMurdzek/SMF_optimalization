# SMF Orchestration Model - Combined Notes

## Model Overview
Minimalny model decyzyjny dla orkiestracji SMF (Session Management Function):
- Obszary j = 1..J (populacja, regiony ruchowe)
- Kandydaci na SMF k = 1..K (lokalizacje)
- Każda lokalizacja k może mieć x[k] instancji (int >=0)
- assign[j,k] = 1 jeśli obszar j obsługuje SMF w lokalizacji k
- Minimalizujemy koszt: sum_k cost_per_instance * x[k]

## Parameters

### Population & Traffic
- **J**: liczba obszarów (obszary ruchowe np. miasta czy regiony)
- **K**: liczba kandydatów na lokalizacje SMF (np. 2 dla operatora)
- **pop**: populacja w obszarach
- **req_per_person**: żądania/s na osobę (może być ten sam dla wszystkich)
  - *TODO*: Podmienić na ruch w lokalizacji
- **tau**: średni czas trwania sesji [s]
- **active_sessions[j]**: pop[j] * req_per_person[j] * tau

### Latency
- **latency**: parametr pomocniczy (można nie używać)
- **latency_kj**: opóźnienie lokalizacja k -> obszar j [ms]
- **Lmax**: dopuszczalne opóźnienie [ms]

### Capacity & Resources
- **C**: pojemność jednej instancji SMF (liczba sesji)
- **Nmin**: minimalna liczba instancji na lokalizację (np. 0 lub 1)
  - *NOTE*: Zbędne minimalne, maksymalna liczba powinna być na podstawie zasobów!
- **Nmax**: maksymalna liczba instancji na lokalizację

### Cost
- **cost_per_instance**: koszt jednej instancji (jednostki kosztu)
- **alpha_scale**: parametr kary za skalowanie (opcjonalnie)

## Decision Variables
- **x[k]**: ile instancji na lokalizacji k (0..Nmax)
- **assign[j,k]**: przypisanie obszaru j do lokalizacji k (0/1)

## Constraints

### Assignment Constraints
1. **Każdy obszar przypisany do dokładnie jednej lokalizacji** (Zostaje):
   ```
   forall(j in 1..J) ( sum(k in 1..K)(assign[j,k]) = 1 )
   ```

2. **Przypisanie do lokalizacji dozwolone tylko jeśli latency <= Lmax** (Zostaje):
   ```
   forall(j in 1..J, k in 1..K) (
       assign[j,k] = 1 -> latency_kj[k,j] <= Lmax
   )
   ```

### Active Sessions (Zostaje, ale można uprościć)
```
constraint forall(j in 1..J)(
    active_sessions[j] = pop[j] * req_per_person[j] * tau
)
```

### Capacity Constraints
**Zasada pojemności** (Zostaje): Aktywne sesje muszą zmieścić się w instancjach lokalizacji
```
constraint forall(j in 1..J)(
    sum(k in 1..K)( assign[j,k] * x[k] * C ) >= active_sessions[j]
)
```

**Alternatywna forma** (v2):
```
constraint forall(k in 1..K)(
    x[k] >= Nmin /\ x[k] <= Nmax
)
```

## Objective Function
**Dobre ograniczenie**: Minimalizuj koszt utrzymania instancji + kara za skalowanie (opcjonalna)
```
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );
```

*Opcjonalnie*: Można dodać karę za nierównomierne load/zmiany: `alpha_scale * sum(...)`

## TODO / Future Improvements

1. **Zasoby w lokalizacjach**:
   - W danej lokalizacji w danym serwerze możemy odpalić jakąś ilość instancji
   - Suma zasobów instancji SMF nie może przewyższać zasobów lokalizacji!
   - Jako dane wejściowe dodać mapę zasobów

2. **Topologia sieci**:
   - Dodać mapę topologii między serwerami
   - Który węzeł ma dostęp do którego serwera

3. **Optymalizacja opóźnień**:
   - Dodać minimalizację opóźnienia w funkcji celu

4. **Uproszczenia**:
   - Uprościć wyliczanie active_sessions
   - Usunąć zbędne ograniczenia minimalne
   - Maksymalna liczba instancji powinna być określona na podstawie dostępnych zasobów

## Example Data

### Test Configuration
- **J = 3**: 3 obszary (miasta/regiony)
- **K = 2**: 2 możliwe lokalizacje SMF
- **pop = [100000, 50000, 20000]**: populacja w obszarach
- **req_per_person = [0.00002, 0.00003, 0.000015]**: żądania/s na osobę
- **tau = 600.0**: średni czas trwania sesji 600s (10 min)
- **Lmax = 100.0**: dopuszczalne opóźnienie 100ms
- **C = 10000**: 1 instancja obsługuje 10k sesji
- **Nmin = 0, Nmax = 10**
- **cost_per_instance = 1.0, alpha_scale = 0.0**

### Latency Matrix (k->j in ms)
```
latency_kj:
  k=1: [10.0, 20.0, 150.0]   % dobry dla j1,j2, zły dla j3
  k=2: [70.0, 40.0, 30.0]    % k=2
```
