#define SDL_MAIN_USE_CALLBACKS

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include <stdio.h>
#include <stdlib.h>

static const int WIDTH = 800;
static const int HEIGHT = 600;

typedef struct {
    SDL_Window* window;
    SDL_Renderer* renderer;

    SDL_Gamepad* gamepad;
} AppState;

SDL_AppResult SDL_AppInit(void ** appstate, int argc, char** argv) {
    AppState* app_state = malloc(sizeof(AppState));
    *app_state = (AppState){};
    *appstate = app_state;

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_CAMERA | SDL_INIT_GAMEPAD)) {
        SDL_Log("couldn't initialize properly: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    if (!SDL_CreateWindowAndRenderer("SDL3 Gamepad Demo", WIDTH, HEIGHT, 0, &(app_state->window), &(app_state->renderer))) {
        SDL_Log("couldn't initialize window/renderer properly: %s", SDL_GetError());
        return SDL_APP_FAILURE;

    }

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void* appstate) {

    AppState* app_state = appstate;

    SDL_Gamepad* gamepad = app_state->gamepad;
    if (gamepad) {  /* we have a stick opened? */

        Sint16 leftx = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_LEFTX);
        Sint16 lefty = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_LEFTY);

        Sint16 rightx = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_RIGHTX);
        Sint16 righty = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_RIGHTY);

        Sint16 left_trigger = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER);
        Sint16 right_trigger = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER);

        SDL_Log("left_x: %d, left_y: %d", leftx, lefty);
        SDL_Log("right_x: %d, right_y: %d", rightx, righty);
        SDL_Log("left_trigger: %d, right_trigger: %d", left_trigger, right_trigger);
    }

    SDL_Renderer* renderer = app_state->renderer;

    const double now = ((double)SDL_GetTicks()) / 1000.0;  /* convert from milliseconds to seconds. */
    const float red = (float) (0.5 + 0.5 * SDL_sin(now));
    const float green = (float) (0.5 + 0.5 * SDL_sin(now + SDL_PI_D * 2 / 3));
    const float blue = (float) (0.5 + 0.5 * SDL_sin(now + SDL_PI_D * 4 / 3));

    SDL_SetRenderDrawColorFloat(renderer, red, green, blue, SDL_ALPHA_OPAQUE_FLOAT);  /* new color, full alpha. */
    /* clear the window to the draw color. */
    SDL_RenderClear(renderer);

    /* put the newly-cleared rendering on the screen. */
    SDL_RenderPresent(renderer);

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event *event) {
    AppState* app_state = (AppState*) appstate;

    if (event->type == SDL_EVENT_QUIT) {
        return SDL_APP_SUCCESS;
    } else if (event->type == SDL_EVENT_GAMEPAD_ADDED) {
        if (app_state->gamepad == NULL) {
            SDL_Gamepad* pad = SDL_OpenGamepad(event->gdevice.which);
            if (!pad) {
                SDL_Log("Failed to open gamepad ID %u: %s", (unsigned int) event->gdevice.which, SDL_GetError());
            } else {
                const char* gamepad_name = SDL_GetGamepadName(pad);
                SDL_Log("Opening gamepad ID: %u", event->gdevice.which);
                SDL_Log("Gamepad name: %s", gamepad_name);
                app_state->gamepad = pad;
            }
        }
    } else if (event->type == SDL_EVENT_GAMEPAD_REMOVED) {
        SDL_Log("Removing gamepad ID: %u", event->gdevice.which);
        if (app_state->gamepad && (SDL_GetGamepadID(app_state->gamepad) == event->gdevice.which)) {
            SDL_CloseGamepad(app_state->gamepad);  /* our controller was unplugged. */
            app_state->gamepad = NULL;
        }
    }
    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate, SDL_AppResult result) {}
