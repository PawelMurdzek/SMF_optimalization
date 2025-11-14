% smf_orchestration.mzn
%
% Minimalny model decyzyjny:
% - obszary j = 1..J (populacja)
% - kandydatów na SMF k = 1..K (lokalizacje)
% - każda lokalizacja k może mieć x[k] instancji (int >=0)
% - assign[j,k] = 1 jeśli obszar j obsługuje SMF w lokalizacji k
% - ograniczenie: aktywne_sesje[j] <= sum_k assign[j,k] * x[k] * C
% - assign dopuszczalne tylko gdy latency[k,j] <= Lmax
% - minimalizujemy koszt: sum_k cost_per_instance * x[k]

int: J;               % liczba obszarów
int: K;               % liczba kandydatów na lokalizacje SMF

array[1..J] of int: pop;          % populacja w obszarach
array[1..J] of float: req_per_person;  % żądania/s na osobę (może być ten sam dla wszystkich)
float: tau;            % średni czas trwania sesji [s]
% aktywne_sesje[j] = pop[j] * req_per_person[j] * tau

array[1..K] of float: latency;    % param. pomocnicze (można nie używać) 
array[1..K,1..J] of float: latency_kj; % opóźnienie lokalizacja k -> obszar j [ms]
float: Lmax;           % dopuszczalne opóźnienie [ms]

int: C;                % pojemność jednej instancji SMF (liczba sesji)
int: Nmin;             % minimalna liczba instancji na lokalizację (np. 0 lub 1)
int: Nmax;             % maksymalna liczba instancji na lokalizację

float: cost_per_instance;   % koszt jednej instancji (jednostki kosztu)
float: alpha_scale;        % parametr kary za skalowanie (opcjonalnie)

% --- zmienne decyzyjne ---
array[1..K] of var 0..Nmax: x;            % ile instancji na lokalizacji k
array[1..J,1..K] of var 0..1: assign;     % przypisanie obszaru j do lokalizacji k (0/1)

% Każdy obszar przypisany do dokładnie jednej lokalizacji
constraint forall(j in 1..J) ( sum(k in 1..K)(assign[j,k]) = 1 );

% Przypisanie do lokalizacji dozwolone tylko jeśli latency <= Lmax
constraint forall(j in 1..J, k in 1..K) (
    assign[j,k] = 1 -> latency_kj[k,j] <= Lmax
);

% Wyliczamy liczbę oczekiwanych aktywnych sesji w obszarze j
array[1..J] of var float: active_sessions;
constraint forall(j in 1..J)(
    active_sessions[j] = pop[j] * req_per_person[j] * tau
);
%tu uproscic mozna

% Zasada pojemności: aktywne sesje muszą zmieścić się w instancjach lokalizacji
% Jeśli obszar j przypisany do k: active_sessions[j] <= x[k] * C
constraint forall(j in 1..J)(
    sum(k in 1..K)( assign[j,k] * x[k] * C ) >= active_sessions[j]
);

% Minimalne/ maksymalne instancje
constraint forall(k in 1..K)(
    x[k] * C >= sum(j in 1..J)( assign[j,k] * active_sessions[j] )
);
%zbedne minimalne, maksymalna liczba na podstawie zasobow!

% w danej lokalizacji w danym serwerze mozemy odpalic jakas ilosc instacji
% suma zasobow instacji SMF nie moze przewyzszac zasobow lokalizacji!!!!
% jako dane wejsciowe dodac mape zasobow
% dodac mape topologii miedzy serwerami
%ktory wezel ma dostep do ktorego serwera


% Funkcja celu: minimalizuj koszt utrzymania instancji + kara za skalowanie (opcjonalna)
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );
% (opcjonalnie można dodać karę za nierównomierne load/zmiany: alpha_scale * sum(...))

%dodac minimalizacje opoznienia w fukcji celu

solve minimize total_cost;

output [
  "x = " ++ show(x) ++ "\n",
  "assign = " ++ show(assign) ++ "\n",
  "active_sessions = " ++ show(active_sessions) ++ "\n",
  "total_cost = " ++ show(total_cost) ++ "\n"
];
