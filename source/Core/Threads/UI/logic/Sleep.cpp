#include "OperatingModes.h"
#include "ui_drawing.hpp"
OperatingMode gui_SolderingSleepingMode(const ButtonState buttons, guiContext *cxt) {
#ifdef NO_SLEEP_MODE
  return OperatingMode::Soldering;
#endif
  // Drop to sleep temperature and display until movement or button press

  // user moved or pressed a button, go back to soldering
  // If in the first two seconds we disable this to let accelerometer warm up

#ifdef POW_DC
  if (checkForUnderVoltage()) {
    return OperatingMode::HomeScreen; // return non-zero on error
  }
#endif

  if (cxt->scratch_state.state4) {
    // Hibernating mode
    currentTempTargetDegC = 0;
  } else {
    // see https://github.com/Ralim/IronOS/issues/2033 for more details on this
    uint16_t sleepTemp     = getSettingValue(SettingsOptions::SleepTemp);
    uint16_t solderingTemp = getSettingValue(SettingsOptions::SolderingTemp);
    uint16_t targetTemp    = getSettingValue(SettingsOptions::AutoStartMode) == autoStartMode_t::SLEEP ? sleepTemp : min(solderingTemp, sleepTemp);
    currentTempTargetDegC  = getSettingValue(SettingsOptions::TemperatureInF) ? TipThermoModel::convertFtoC(targetTemp) : targetTemp;
  }
  // draw the lcd
  uint16_t tipTemp = getSettingValue(SettingsOptions::TemperatureInF) ? TipThermoModel::getTipInF() : TipThermoModel::getTipInC();

  if (getSettingValue(SettingsOptions::DetailedSoldering)) {
    ui_draw_soldering_detailed_sleep(tipTemp);
  } else {
    ui_draw_soldering_basic_sleep(tipTemp);
  }

  if (!shouldBeSleeping()) {
    return cxt->previousMode;
  }

  if (shouldShutdown()) {
    // shutdown
    currentTempTargetDegC = 0;
    return OperatingMode::HomeScreen;
  }
  if (cxt->scratch_state.state4) {
    return OperatingMode::Hibernating;
  } else {
    return OperatingMode::Sleeping;
  }
}
