# Focus

*a *aaa ***A **simple** ***editor*** *whose* goal is to get out of your*** way and let you do *work.*

---

## Blockquotes!

> # A blockquote
>
>> A deeper
>> blockquote
>>> Deeper still
> Back out

```jai
main :: () {
    // My jai program
    foo := 100;
    print("Look at % things!\n", foo);

    my_jai_program_has_markdown :: #string __md
        # title of my book

        It was a dark and stormy night... in which I wrote some jai
        ```jai
        foo :: () {
            print("Foo!\n");
        }
        ```
    __md;

}
```

---

## More stuff

>
> This editor is for people who value simplicity, are sensitive to input latency and do not require heavy language support in their editor.
>

![focus](https://user-images.githubusercontent.com/119373822/236081314-45d53952-7a6c-4d6b-8773-e5b49d1dbdab.gif)

---

## Quick start

1. [Download the executable](https://github.com/focus-editor/focus/releases) and put it somewhere where it will live.
asa
2. Launch the executable. Once launched, it will generate its configuration files.
    * On **Windows**, it will create a `global.focus-config` file and a `projects` folder next to itself.
    * On **Mac**, these files will be found in `/Users/YOURNAME/Library/Application Support/dev.focus-editor/`.
    * On **Linux**, these files will be found in `${XDG_CONFIG_HOME}/focus-editor/` (which usually expands to `${HOME}/.config/focus-editor`).

3. Open the global config file by using the command `Open Global Config` - you can find the shortcut to show commands on the welcome screen.

4. This editor expects that you tell it what folders it should add to the workspace. You do it by either editing the global config file for your default workspace, or by creating a project (see below)

5. A project in this editor is just a config file that lives in `projects/Project Name.focus-config`. There's an example project config file provided. You just edit the file and then activate the project by using the `Switch To Project` command.
