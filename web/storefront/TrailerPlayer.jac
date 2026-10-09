"""A movie's trailer on the storefront (P8.4): the movie page and the chat's movie card.

Nothing loads until the visitor presses Play trailer: then the player (YouTube's
privacy-enhanced youtube-nocookie.com, or Vimeo's) appears in a 16:9 frame and starts.
`embed` is the server's trailer_embed, built from a checked link
(core/catalog/trailer.jac); anything else is never framed.
"""

import from react { useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { PlayIcon }
import from ...components.ui.button { Button }

glob PLAYERS: list[str] = [
         "https://www.youtube-nocookie.com/embed/",
         "https://player.vimeo.com/video/"
     ];

def:pub playable(embed: str) -> bool {
    # Only the two players the server builds are ever framed.
    for prefix in PLAYERS {
        if embed.startswith(prefix) {
            return True;
        }
    }
    return False;
}

def:pub TrailerPlayer(embed: str, title: str) -> JsxElement {
    [playing, set_playing] = useState(False);
    if not playable(embed) {
        return <span hidden={True}></span>;
    }
    if not playing {
        return
            <Button
                type="button"
                data-testid="play-trailer"
                className="min-h-11 gap-2 px-5"
                onClick={lambda { set_playing(True); }}
            >
                <HugeiconsIcon icon={PlayIcon} strokeWidth={2} aria-hidden="true"/>
                Play trailer
            </Button>;
    }
    return
        <div
            data-testid="trailer"
            className="relative aspect-video w-full overflow-hidden rounded-lg bg-black"
        >
            <iframe
                src={embed + "?autoplay=1"}
                title={f"{title}: trailer"}
                allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
                allowFullScreen={True}
                referrerPolicy="strict-origin-when-cross-origin"
                className="absolute inset-0 h-full w-full border-0"
            ></iframe>
        </div>;
}
