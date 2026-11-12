import '../models/game_state.dart';

enum EngineMode { fullExploit, regGto }

/// Perfil por defecto cuando no hay lectura individual (capa de aplicación).
/// FULL_EXPLOIT: NL2-NL25 => poolDefault (priors MDA); NL50-NL200 sin HUD => Reg_GTO (Unknown_Reg: activa el
/// Anti_Counter_Exploit_Shield, cierra el vector NL50 de la auditoría 9.55). regGto => siempre gtoBase.
class ProfileDefaults {
  ProfileDefaults._();

  static const defaultMode = EngineMode.fullExploit;

  static VillainProfile defaultFor(Stake stake, {EngineMode mode = defaultMode}) =>
      mode == EngineMode.fullExploit && stake.index <= Stake.nl25.index ? VillainProfile.poolDefault : VillainProfile.gtoBase;
}
