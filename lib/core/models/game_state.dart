import 'cards.dart';

export 'cards.dart';

enum RakeTier { microHighRake, midRake }

enum Stake {
  nl2(0.02),
  nl5(0.05),
  nl10(0.10),
  nl25(0.25),
  nl50(0.50),
  nl100(1.00),
  nl200(2.00);

  const Stake(this.bigBlind);
  final double bigBlind;

  RakeTier get rakeTier =>
      index <= Stake.nl25.index ? RakeTier.microHighRake : RakeTier.midRake;
}

/// Orden preflop. Postflop: SB actúa primero, BTN último.
enum Position {
  utg,
  mp,
  co,
  btn,
  sb,
  bb;

  int get postflopOrder => switch (this) { sb => 0, bb => 1, _ => index + 2 };
  bool isInPositionVs(Position other) => postflopOrder > other.postflopOrder;
}

enum Street { preflop, flop, turn, river }

enum ActionType { fold, check, call, bet, raise, allIn }

enum PotType { limped, srp, threeBet, fourBetPlus }

enum VillainProfile { gtoBase, nit, callingStation, maniac, regAbc, regAgro, trapperPremium }

/// Insta < 1.5s, normal 2-5s, long tank > 8s.
enum TimingTell { none, instaAction, normalTiming, longTank }

class PlayerAction {
  const PlayerAction(this.street, this.actor, this.type, [this.amountBb = 0, this.timing = TimingTell.none]);
  final Street street;
  final Position actor;
  final ActionType type;
  final double amountBb;
  final TimingTell timing;

  bool get isAggressive =>
      type == ActionType.bet || type == ActionType.raise || type == ActionType.allIn;
}

class GameState {
  GameState({
    required this.stake,
    required this.heroPosition,
    this.villainPosition,
    this.effectiveStackBb,
    this.potBb,
    this.hero,
    List<Card> board = const [],
    List<PlayerAction> actions = const [],
    this.villainProfile = VillainProfile.gtoBase,
    this.activePlayers = 2,
  })  : board = List.unmodifiable(board),
        actions = List.unmodifiable(actions) {
    if (board.length > 5 || board.length == 1 || board.length == 2) {
      throw ArgumentError('Board debe tener 0, 3, 4 o 5 cartas');
    }
    final mask = board.fold<int>(hero?.mask ?? 0, (m, c) {
      if (m & c.bit != 0) throw ArgumentError('Carta duplicada: $c');
      return m | c.bit;
    });
    deadMask = mask;
  }

  final Stake stake;
  final Position heroPosition;
  final Position? villainPosition;
  final double? effectiveStackBb;
  final double? potBb;
  final HoleCards? hero;
  final List<Card> board;
  final List<PlayerAction> actions;
  final VillainProfile villainProfile;

  /// Jugadores activos en el bote (>=3 => multiway).
  final int activePlayers;
  late final int deadMask;

  GameState copyWith({VillainProfile? villainProfile, List<PlayerAction>? actions, HoleCards? hero}) => GameState(
        stake: stake,
        heroPosition: heroPosition,
        villainPosition: villainPosition,
        effectiveStackBb: effectiveStackBb,
        potBb: potBb,
        hero: hero ?? this.hero,
        board: board,
        actions: actions ?? this.actions,
        villainProfile: villainProfile ?? this.villainProfile,
        activePlayers: activePlayers,
      );

  RakeTier get rakeTier => stake.rakeTier;

  Street get street => switch (board.length) {
        0 => Street.preflop,
        3 => Street.flop,
        4 => Street.turn,
        _ => Street.river,
      };

  String? get heroHandClass => hero?.handClass;

  Iterable<PlayerAction> get _preflopRaises => actions.where(
      (a) => a.street == Street.preflop && a.isAggressive);

  PotType get potType => switch (_preflopRaises.length) {
        0 => PotType.limped,
        1 => PotType.srp,
        2 => PotType.threeBet,
        _ => PotType.fourBetPlus,
      };

  Position? get preflopAggressor =>
      _preflopRaises.isEmpty ? null : _preflopRaises.last.actor;

  double? get spr => (effectiveStackBb != null && potBb != null && potBb! > 0)
      ? effectiveStackBb! / potBb!
      : null;

  bool? get heroInPosition =>
      villainPosition == null ? null : heroPosition.isInPositionVs(villainPosition!);

  /// Variables obligatorias ausentes para evaluar postflop (regla anti-alucinación #3).
  List<String> missingForPostflop() => [
        if (hero == null) 'hero',
        if (villainPosition == null) 'villainPosition',
        if (effectiveStackBb == null) 'effectiveStackBb',
        if (potBb == null) 'potBb',
        if (board.length < 3) 'board',
        if (preflopAggressor == null && potType != PotType.limped) 'actions(preflop aggressor)',
      ];

  List<String> missingForPreflop() => [if (hero == null) 'hero'];
}
