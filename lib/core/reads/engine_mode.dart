import '../models/game_state.dart';

enum EngineMode { fullExploit, regGto }

/// Perfil por defecto cuando no hay lectura individual (capa de aplicación).
/// FULL_EXPLOIT: NL2-NL50 => poolDefault (priors MDA); NL100-NL200 => Reg_GTO. regGto => siempre gtoBase.
class ProfileDefaults {
  ProfileDefaults._();

  static const defaultMode = EngineMode.fullExploit;

  static VillainProfile defaultFor(Stake stake, {EngineMode mode = defaultMode}) =>
      mode == EngineMode.fullExploit && stake.index <= Stake.nl50.index ? VillainProfile.poolDefault : VillainProfile.gtoBase;
}
